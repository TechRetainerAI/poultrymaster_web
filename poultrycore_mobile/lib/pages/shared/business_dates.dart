// Business dates: "yyyy-MM-dd" strings on the company's calendar, handled as
// strings — never through DateTime.parse into local time, which can shift a
// day. Mirrors lib/activity/completeness.ts and lib/closing/daily-closing.ts.

const _short = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _long = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
  'October', 'November', 'December',
];
const _weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/// The "yyyy-MM-dd" part of [value], or null when it is not a real date.
String? toBusinessDate(Object? value) {
  final s = '${value ?? ''}';
  if (s.length < 10) return null;
  final d = s.substring(0, 10);
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(d);
  if (m == null) return null;
  final month = int.parse(m.group(2)!), day = int.parse(m.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return d;
}

(int, int, int)? _parts(Object? v) {
  final d = toBusinessDate(v);
  if (d == null) return null;
  final p = d.split('-').map(int.parse).toList();
  return (p[0], p[1], p[2]);
}

/// "Sep 12".
String formatShortDate(Object? value) {
  final p = _parts(value);
  return p == null ? '—' : '${_short[p.$2 - 1]} ${p.$3}';
}

/// "September 12, 2026".
String formatLongDate(Object? value) {
  final p = _parts(value);
  return p == null ? '—' : '${_long[p.$2 - 1]} ${p.$3}, ${p.$1}';
}

/// "Sat, Sep 12".
String formatWeekdayDate(Object? value) {
  final p = _parts(value);
  if (p == null) return '—';
  final wd = DateTime.utc(p.$1, p.$2, p.$3).weekday % 7; // Sunday = 0
  return '${_weekdays[wd]}, ${formatShortDate(value)}';
}

/// A business date moved by whole days, in UTC so no daylight-saving gap
/// skips a day.
String? shiftBusinessDate(Object? value, int days) {
  final p = _parts(value);
  if (p == null) return null;
  return isoDay(DateTime.utc(p.$1, p.$2, p.$3 + days));
}

/// "yyyy-MM-dd" for a DateTime's calendar day.
String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A business date as a DateTime for a date picker (midnight, local).
DateTime? businessDateAsDateTime(Object? value) {
  final p = _parts(value);
  return p == null ? null : DateTime(p.$1, p.$2, p.$3);
}

/// "today" / "yesterday" / "3 days ago", relative to the business date.
String daysAgoLabel(Object? date, Object? businessDate) {
  final a = _parts(date), b = _parts(businessDate);
  if (a == null || b == null) return '';
  final n = DateTime.utc(b.$1, b.$2, b.$3).difference(DateTime.utc(a.$1, a.$2, a.$3)).inDays;
  if (n <= 0) return 'today';
  if (n == 1) return 'yesterday';
  return '$n days ago';
}

/// A number with thousands separators and at most [digits] decimals, as
/// toLocaleString(undefined, { maximumFractionDigits }) writes it.
String fmtNum(num? n, [int digits = 1]) {
  if (n == null || !n.isFinite) return '—';
  var s = n.toStringAsFixed(digits);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  final neg = s.startsWith('-');
  if (neg) s = s.substring(1);
  final parts = s.split('.');
  final whole = parts[0];
  final b = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
    b.write(whole[i]);
  }
  return '${neg ? '-' : ''}$b${parts.length > 1 ? '.${parts[1]}' : ''}';
}

/// A server instant ("…Z", or naive and therefore UTC) on the company's clock,
/// as the web's formatInstant: "12 Sep 2026, 15:04". [offset] is the company's
/// UTC offset (see CompanyClock); the phone's own zone is never used.
String fmtInstant(Object? value, Duration offset) {
  final s = '${value ?? ''}'.trim();
  if (s.isEmpty) return '';
  final zoned = RegExp(r'([Zz]|[+-]\d{2}:?\d{2})$').hasMatch(s);
  final d = DateTime.tryParse(zoned ? s : '${s.replaceFirst(' ', 'T')}Z');
  if (d == null) return '';
  final l = d.toUtc().add(offset);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.day} ${_short[l.month - 1]} ${l.year}, ${two(l.hour)}:${two(l.minute)}';
}

/// The web's fmtDateTime: "17 Sep 2026, 11:56" — the row's business date with
/// the time it was entered (createdDate / createdAt / dateCreated / createdOn)
/// on the company clock; failing that the business date's own time unless it
/// is midnight; failing that the date alone.
String fmtDateTime(Object? businessDate, Map? row, Duration offset) {
  final s = '${businessDate ?? ''}'.trim();
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (m == null) return '';
  final date = '${int.parse(m[3]!)} ${_short[int.parse(m[2]!) - 1]} ${m[1]}';
  String? time(Object? v) {
    final full = fmtInstant(v, offset);
    final at = full.lastIndexOf(', ');
    return at > 0 ? full.substring(at + 2) : null;
  }

  if (row != null) {
    for (final k in const ['createdDate', 'createdAt', 'dateCreated', 'createdOn']) {
      final v = row[k];
      if (v is String && v.trim().isNotEmpty) {
        final t = time(v);
        return t == null ? date : '$date, $t';
      }
    }
  }
  if (s.length > 10 && !RegExp(r'T?00:00:00(\.0+)?$').hasMatch(s)) {
    final t = time(s);
    if (t != null && t != '00:00') return '$date, $t';
  }
  return date;
}
