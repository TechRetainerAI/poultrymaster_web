import '../../api/api_client.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import 'business_dates.dart';

/// The company's calendar and clock from `/CompanyTime/context`, as the web's
/// useBusinessDate + useCompanyDateTime: today's business date, and the UTC
/// offset that instants are shown in. Never the phone's clock, except as the
/// last resort when the server cannot be asked.
class CompanyClock {
  const CompanyClock(this.today, this.offset);
  final String today;
  final Duration offset;

  String instant(Object? value) => fmtInstant(value, offset);

  static Future<CompanyClock> load(Session session, Company company) async {
    try {
      final c = await session.farmClient.get('/api/CompanyTime/context', query: {'farmId': company.farmId});
      if (c is Map) {
        final today = toBusinessDate(c['businessDate']);
        if (today != null) return CompanyClock(today, offsetOf(c['companyLocalDateTime'], c['utcNow']));
      }
    } on ApiException {
      // fall through
    }
    final now = DateTime.now();
    return CompanyClock(isoDay(now), now.timeZoneOffset);
  }

  /// The offset between a company wall-clock reading and the same instant in
  /// UTC, to the quarter hour. Zero when either is missing.
  static Duration offsetOf(Object? local, Object? utc) {
    DateTime? naive(Object? v) {
      final s = '${v ?? ''}'.replaceFirst(RegExp(r'([Zz]|[+-]\d{2}:?\d{2})$'), '');
      return s.isEmpty ? null : DateTime.tryParse('${s}Z');
    }
    final l = naive(local), u = naive(utc);
    if (l == null || u == null) return Duration.zero;
    final minutes = l.difference(u).inMinutes;
    return Duration(minutes: (minutes / 15).round() * 15);
  }
}
