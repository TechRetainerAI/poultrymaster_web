// The Days / Weeks / Months / Years picker over the dashboard charts (user,
// 2026-11-02: "we need to have a way to select it: days, weekly, monthly,
// yearly"). One choice drives both kinds of chart:
// - the column charts group their figures into the period's buckets
//   (14 days, 12 weeks from Monday, 12 months, 5 years), oldest first;
// - the pie charts cover the same window (from the first bucket to today).
// Used by the Poultry, Water, Restaurant, Generic and Hotel dashboards.
//
// A fifth choice, Range (user, 2026-11-09: "the user can choose ... a date
// range under which they want to visualize the data"), opens a calendar. The
// charts then cover exactly those dates, grouped by day, week, month or year
// depending on how long the range is (see [ChartWindow.range]).

import 'package:flutter/material.dart';

import 'package:poultrycore_mobile/design/tone.dart';
enum ChartPeriod { days, weeks, months, years }

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One column of a chart: the dates it covers (inclusive), and how it reads.
class ChartBucket {
  const ChartBucket({required this.from, required this.to, required this.short, required this.long});
  final String from, to;

  /// Under the column ("Today", "3/11", "Nov", "2026").
  final String short;

  /// In the read-out when the column is tapped ("Mon 3 Nov", "Week of 3 Nov", "November 2026").
  final String long;

  bool holds(String isoDay) => isoDay.compareTo(from) >= 0 && isoDay.compareTo(to) <= 0;
}

extension ChartPeriodX on ChartPeriod {
  String get label => const {ChartPeriod.days: 'Days', ChartPeriod.weeks: 'Weeks', ChartPeriod.months: 'Months', ChartPeriod.years: 'Years'}[this]!;

  /// "last 14 days", for subtitles and the middle of the pies.
  String get window => const {
        ChartPeriod.days: 'last 14 days',
        ChartPeriod.weeks: 'last 12 weeks',
        ChartPeriod.months: 'last 12 months',
        ChartPeriod.years: 'last 5 years',
      }[this]!;

  /// "day by day", for subtitles.
  String get by => const {ChartPeriod.days: 'day by day', ChartPeriod.weeks: 'week by week', ChartPeriod.months: 'month by month', ChartPeriod.years: 'year by year'}[this]!;

  /// The columns, oldest first; the last one holds [now].
  List<ChartBucket> buckets(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (this) {
      case ChartPeriod.days:
        return [
          for (var i = 13; i >= 0; i--)
            () {
              final d = today.subtract(Duration(days: i));
              return ChartBucket(
                from: _iso(d),
                to: _iso(d),
                short: i == 0 ? 'Today' : '${d.day}',
                long: '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}',
              );
            }(),
        ];
      case ChartPeriod.weeks:
        final monday = today.subtract(Duration(days: today.weekday - 1));
        return [
          for (var i = 11; i >= 0; i--)
            () {
              final s = monday.subtract(Duration(days: 7 * i));
              final e = s.add(const Duration(days: 6));
              return ChartBucket(
                from: _iso(s),
                to: _iso(e),
                short: i == 0 ? 'Now' : '${s.day}/${s.month}',
                long: 'Week of ${s.day} ${_months[s.month - 1]}',
              );
            }(),
        ];
      case ChartPeriod.months:
        return [
          for (var i = 11; i >= 0; i--)
            () {
              final s = DateTime(today.year, today.month - i, 1);
              final e = DateTime(s.year, s.month + 1, 0);
              return ChartBucket(from: _iso(s), to: _iso(e), short: _months[s.month - 1], long: '${_monthNames[s.month - 1]} ${s.year}');
            }(),
        ];
      case ChartPeriod.years:
        return [
          for (var i = 4; i >= 0; i--)
            ChartBucket(from: '${today.year - i}-01-01', to: '${today.year - i}-12-31', short: '${today.year - i}', long: '${today.year - i}'),
        ];
    }
  }
}

/// Sums [amount] of the [rows] falling in each bucket, by the row's ISO day.
List<num> bucketSums(List<ChartBucket> buckets, Iterable<Map> rows, String Function(Map r) dayOfRow, num Function(Map r) amount) {
  final out = List<num>.filled(buckets.length, 0);
  if (buckets.isEmpty) return out;
  final first = buckets.first.from, last = buckets.last.to;
  for (final r in rows) {
    final d = dayOfRow(r);
    if (d.length < 10 || d.compareTo(first) < 0 || d.compareTo(last) > 0) continue;
    for (var i = 0; i < buckets.length; i++) {
      if (buckets[i].holds(d)) {
        out[i] += amount(r);
        break;
      }
    }
  }
  return out;
}

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _nextDay(DateTime d) => DateTime(d.year, d.month, d.day + 1);
String _dm(DateTime d) => '${d.day} ${_months[d.month - 1]}';
String _dmy(DateTime d) => '${_dm(d)} ${d.year}';

/// The column holding [isoDay] (drawn as "today"), or null when the window
/// does not reach it (a range in the past).
String? bucketHolding(List<ChartBucket> buckets, String isoDay) {
  for (final b in buckets) {
    if (b.holds(isoDay)) return b.from;
  }
  return null;
}

/// The last day the pies count: today, or the range's last day when the range
/// ends before today (so a past range never takes in later rows).
String windowEnd(List<ChartBucket> buckets, String today) =>
    buckets.isNotEmpty && buckets.last.to.compareTo(today) < 0 ? buckets.last.to : today;

/// What the charts show: one of the four fixed periods ending today, or a
/// date range the user picked.
@immutable
class ChartWindow {
  const ChartWindow.preset(this.period)
      : from = null,
        to = null;

  /// [a] to [z], both days included. The grouping follows the length, so the
  /// columns stay readable on a phone: up to 31 days by day, up to 16 weeks by
  /// week, up to 2 years by month, longer by year.
  ChartWindow.range(DateTime a, DateTime z)
      : from = _dayOnly(a.isAfter(z) ? z : a),
        to = _dayOnly(a.isAfter(z) ? a : z),
        period = _groupFor(_dayOnly(a.isAfter(z) ? z : a), _dayOnly(a.isAfter(z) ? a : z));

  static ChartPeriod _groupFor(DateTime a, DateTime z) {
    final days = DateTime.utc(z.year, z.month, z.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays + 1;
    if (days <= 31) return ChartPeriod.days;
    if (days <= 16 * 7) return ChartPeriod.weeks;
    if (days <= 731) return ChartPeriod.months;
    return ChartPeriod.years;
  }

  /// For a preset, the period; for a range, how its columns are grouped.
  final ChartPeriod period;
  final DateTime? from, to;

  bool get isRange => from != null;

  /// "last 12 months", or "3 Mar – 20 Apr 2026", for subtitles and the middle of the pies.
  String get window {
    if (!isRange) return period.window;
    final a = from!, z = to!;
    if (a == z) return _dmy(a);
    return a.year == z.year ? '${_dm(a)} – ${_dmy(z)}' : '${_dmy(a)} – ${_dmy(z)}';
  }

  /// "in the last 12 months", or "between 3 Mar and 20 Apr 2026", for empty-chart messages.
  String get inWindow {
    if (!isRange) return 'in the ${period.window}';
    final a = from!, z = to!;
    if (a == z) return 'on ${_dmy(a)}';
    return a.year == z.year ? 'between ${_dm(a)} and ${_dmy(z)}' : 'between ${_dmy(a)} and ${_dmy(z)}';
  }

  /// "day by day", for subtitles.
  String get by => period.by;

  /// The columns, oldest first.
  List<ChartBucket> buckets(DateTime now) {
    if (!isRange) return period.buckets(now);
    final today = _iso(_dayOnly(now));
    final out = <ChartBucket>[];
    var s = from!;
    while (!s.isAfter(to!)) {
      DateTime e;
      String short, long;
      switch (period) {
        case ChartPeriod.days:
          e = s;
          short = _iso(s) == today ? 'Today' : '${s.day}';
          long = '${_weekdays[s.weekday - 1]} ${_dmy(s)}';
        case ChartPeriod.weeks:
          // Weeks run Monday to Sunday; the first and last are cut to the range.
          e = DateTime(s.year, s.month, s.day + 7 - s.weekday);
          if (e.isAfter(to!)) e = to!;
          short = '${s.day}/${s.month}';
          long = s == e ? _dmy(s) : '${_dm(s)} – ${_dmy(e)}';
        case ChartPeriod.months:
          e = DateTime(s.year, s.month + 1, 0);
          if (e.isAfter(to!)) e = to!;
          short = _months[s.month - 1];
          long = '${_monthNames[s.month - 1]} ${s.year}';
        case ChartPeriod.years:
          e = DateTime(s.year, 12, 31);
          if (e.isAfter(to!)) e = to!;
          short = '${s.year}';
          long = '${s.year}';
      }
      out.add(ChartBucket(from: _iso(s), to: _iso(e), short: short, long: long));
      s = _nextDay(e);
    }
    return out;
  }

  @override
  bool operator ==(Object other) => other is ChartWindow && other.period == period && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(period, from, to);
}

/// The picker drawn above the charts: Days, Weeks, Months, Years, and Range
/// (a calendar for any dates). With a range chosen, a line under it reads the
/// dates back, with Change and a cross to go back to Months.
class ChartPeriodPicker extends StatelessWidget {
  const ChartPeriodPicker({super.key, required this.value, required this.onChanged, this.now});
  final ChartWindow value;
  final ValueChanged<ChartWindow> onChanged;

  /// Today, for the calendar's last day and its starting range (the clock when null).
  final DateTime? now;

  Future<void> _pickRange(BuildContext context) async {
    final today = _dayOnly(now ?? DateTime.now());
    final last = value.isRange && value.to!.isAfter(today) ? value.to! : today;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: last,
      currentDate: today,
      initialDateRange: value.isRange
          ? DateTimeRange(start: value.from!, end: value.to!)
          : DateTimeRange(start: DateTime(today.year, today.month, 1), end: today),
      helpText: 'Show the charts for',
      saveText: 'Show',
    );
    if (picked != null) onChanged(ChartWindow.range(picked.start, picked.end));
  }

  Widget _segment(String label, bool on, VoidCallback tap, {IconData? icon}) => Expanded(
        child: Semantics(
          selected: on,
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: tap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: on ? Tone.bg(0xFFFFFFFF) : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                boxShadow: on ? const [BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 1))] : null,
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: on ? const Tone.fg(0xFF0B0B0B) : const Tone.fg(0xFF52514E)),
                  const SizedBox(width: 3),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                      color: on ? const Tone.fg(0xFF0B0B0B) : const Tone.fg(0xFF52514E),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final range = value.isRange;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: const Tone.bg(0xFFF0EFEC), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            for (final p in ChartPeriod.values) _segment(p.label, !range && p == value.period, () => onChanged(ChartWindow.preset(p))),
            _segment('Range', range, () => _pickRange(context), icon: Icons.date_range),
          ]),
        ),
        if (range)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              decoration: BoxDecoration(
                color: const Tone.bg(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Tone.line(0xFFDDD6FE)),
              ),
              child: Row(children: [
                const Icon(Icons.date_range, size: 16, color: Tone.fg(0xFF6D28D9)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: value.window, style: const TextStyle(fontWeight: FontWeight.w700, color: Tone.fg(0xFF0B0B0B))),
                      TextSpan(text: ' · ${value.by}', style: const TextStyle(color: Tone.fg(0xFF52514E))),
                    ]),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                TextButton(onPressed: () => _pickRange(context), child: const Text('Change')),
                IconButton(
                  tooltip: 'Back to Months',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18, color: Tone.fg(0xFF52514E)),
                  onPressed: () => onChanged(const ChartWindow.preset(ChartPeriod.months)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}
