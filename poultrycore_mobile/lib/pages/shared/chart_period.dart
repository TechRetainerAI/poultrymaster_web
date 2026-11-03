// The Days / Weeks / Months / Years picker over the dashboard charts (user,
// 2026-11-02: "we need to have a way to select it: days, weekly, monthly,
// yearly"). One choice drives both kinds of chart:
// - the column charts group their figures into the period's buckets
//   (14 days, 12 weeks from Monday, 12 months, 5 years), oldest first;
// - the pie charts cover the same window (from the first bucket to today).
// Used by the Poultry, Water, Restaurant, Generic and Hotel dashboards.

import 'package:flutter/material.dart';

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

/// The four-way picker drawn above the charts.
class ChartPeriodPicker extends StatelessWidget {
  const ChartPeriodPicker({super.key, required this.value, required this.onChanged});
  final ChartPeriod value;
  final ValueChanged<ChartPeriod> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: const Color(0xFFF0EFEC), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          for (final p in ChartPeriod.values)
            Expanded(
              child: Semantics(
                selected: p == value,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(p),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: p == value ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: p == value ? const [BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 1))] : null,
                    ),
                    child: Text(
                      p.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: p == value ? FontWeight.w700 : FontWeight.w500,
                        color: p == value ? const Color(0xFF0B0B0B) : const Color(0xFF52514E),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );
}
