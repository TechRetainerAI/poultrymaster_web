// Treatment Campaigns (migration 339) — the rules of
// `lib/production/treatment-campaigns.ts`, line for line.
//
// The software records treatment, it does not prescribe it. No dose, duration
// or withdrawal period is built in: a suggested quantity is plain arithmetic on
// the farm's own dose, shown for review. Actual is what posts.

import 'package:flutter/material.dart';

import '../shared/business_dates.dart' show fmtNum;
import 'trackers/tracker_logic.dart' show tNum, tStr;
import 'trackers/tracker_widgets.dart' show TColors;

/// DOSE_BASES: (key, label, short).
const doseBases = [
  ('PerBird', 'per bird per day', '/bird'),
  ('Per1000Birds', 'per 1,000 birds per day', '/1,000 birds'),
  ('PerFlock', 'per flock per day', '/flock'),
];

bool isDoseBasis(Object? v) => v == 'PerBird' || v == 'Per1000Birds' || v == 'PerFlock';

String doseBasisLabel(Object? b) {
  for (final (k, l, _) in doseBases) {
    if (k == b) return l;
  }
  return '';
}

num _round4(num n) => (n * 10000).round() / 10000;

/// "0.5 L per 1,000 birds per day" — the dose exactly as the farm set it.
String? describeDose(Object? dose, Object? basis, Object? unit) {
  if (dose == null || !isDoseBasis(basis)) return null;
  final u = tStr(unit);
  return '${fmtQty(tNum(dose))}${u.isNotEmpty ? ' $u' : ''} ${doseBasisLabel(basis)}';
}

/// The same rule as the server's fnpoultrytreatment_suggest. null when there is
/// no dose, or no bird count to multiply by: never a stand-in figure.
num? suggestQuantity(Object? dose, Object? basis, Object? birds) {
  if (dose == null) return null;
  final d = tNum(dose);
  if (d <= 0 || !isDoseBasis(basis)) return null;
  if (basis == 'PerFlock') return _round4(d);
  if (birds == null) return null;
  final b = tNum(birds);
  if (b <= 0) return null;
  return basis == 'PerBird' ? _round4(d * b) : _round4((d * b) / 1000);
}

/// "2.5" → 2.5; "", "abc", negatives → null. Quantities are typed text.
num? parseQty(String? text) {
  final t = (text ?? '').trim();
  if (t.isEmpty) return null;
  final n = num.tryParse(t);
  if (n == null || !n.isFinite || n < 0) return null;
  return _round4(n);
}

String fmtQty(num? n, [Object? unit]) {
  if (n == null || !n.isFinite) return '—';
  final s = fmtNum(n, 4);
  final u = tStr(unit);
  return u.isNotEmpty ? '$s $u' : s;
}

// ---------------------------------------------------------------------------
// Campaign status
// ---------------------------------------------------------------------------

String campaignStatusLabel(Object? s) => s == 'InProgress' ? 'In Progress' : tStr(s);

/// statusStyle: (border, background, text).
(Color, Color, Color) campaignStatusStyle(Object? s) => switch (s) {
      'Scheduled' => (const Color(0xFFBAE6FD), const Color(0xFFF0F9FF), TColors.sky700),
      'InProgress' => (TColors.amber200, TColors.amber50, TColors.amber800),
      'Completed' => (TColors.emerald200, TColors.emerald50, TColors.emerald700),
      'Cancelled' => (TColors.slate200, TColors.slate100, TColors.slate600),
      _ => (TColors.slate200, Colors.white, TColors.slate600),
    };

DateTime? _utc(String d) {
  if (d.length < 10) return null;
  return DateTime.tryParse('${d.substring(0, 10)}T00:00:00Z');
}

/// Inclusive day count of a YYYY-MM-DD range; 0 when the range is invalid.
int daysInclusive(String start, String end) {
  final a = _utc(start), b = _utc(end);
  if (a == null || b == null || b.isBefore(a)) return 0;
  return b.difference(a).inDays + 1;
}

/// YYYY-MM-DD + n days, in calendar days.
String addDays(String date, int n) {
  final t = _utc(date);
  if (t == null) return date;
  return t.add(Duration(days: n)).toIso8601String().substring(0, 10);
}

/// The days a treatment can be recorded for: start..min(end, today).
List<String> recordableDays(String start, String end, String today) {
  final last = end.compareTo(today) < 0 ? end : today;
  final n = daysInclusive(start, last);
  return [for (var i = 0; i < n; i++) addDays(start, i)];
}

/// Withdrawal runs from the LAST dose actually given, by the farm's own days.
String? withdrawalUntil(String? lastDose, num? days) {
  if (lastDose == null || lastDose.isEmpty || days == null || !days.isFinite) return null;
  return addDays(lastDose.substring(0, 10), days.toInt());
}

// ---------------------------------------------------------------------------
// The day grid
// ---------------------------------------------------------------------------

/// Only an open flock with exactly one production record for the date can be dosed.
String dayRowState(Map r) {
  if (r['postedQuantity'] != null) return 'posted';
  if (r['isClosed'] == true) return 'closed';
  final n = tNum(r['recordCount']).toInt();
  if (n == 1) return 'ok';
  return n == 0 ? 'noRecord' : 'duplicate';
}

typedef DayEntry = ({String state, String actualText});

({num available, num actual, num remaining}) dayTotals(num available, List<DayEntry> rows) {
  final actual = rows.where((r) => r.state == 'ok').fold<num>(0, (s, r) => s + (parseQty(r.actualText) ?? 0));
  return (available: _round4(available), actual: _round4(actual), remaining: _round4(available - actual));
}

/// Why the day cannot be posted yet, or null when it can.
String? dayPostBlocker(({num actual, num remaining}) totals, List<DayEntry> rows,
    {required bool alreadyPosted, required bool campaignOpen, required bool inWindow}) {
  if (!campaignOpen) return 'This campaign is closed — no more treatment can be recorded on it.';
  if (!inWindow) return "Pick a date inside the campaign's dates, up to today.";
  if (alreadyPosted) return 'This day is already recorded. Reverse it in Treatment days to record it again.';
  if (rows.any((r) => r.state == 'ok' && r.actualText.trim().isNotEmpty && parseQty(r.actualText) == null)) {
    return 'One of the quantities is not a number.';
  }
  if (totals.actual <= 0) return 'Enter the quantity given for at least one flock.';
  if (totals.remaining < -0.00005) return 'That is more than the stock on hand.';
  return null;
}
