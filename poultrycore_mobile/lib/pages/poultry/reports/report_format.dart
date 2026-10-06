// Shared formatting and vocabulary for the Poultry reports, ported from the
// web: `lib/currency.ts` (money in the company's currency), `lib/date-ranges.ts`
// (the period presets), `lib/cash/cash-flow.ts` + `lib/api/cash-flow.ts`
// (category and flow-group names) and `lib/cash/cash-flow-analysis.ts`.

import 'dart:math' as math;

import '../../../api/api_client.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../shared/business_dates.dart';

// ------------------------------------------------------------------ money

/// The company's currency settings (`/Water/farm-settings`), as the web's
/// useFarmSettingsStore. Defaults to GHS / GHC with the symbol shown.
class FarmMoney {
  const FarmMoney({this.code = 'GHS', this.symbol = 'GHC', this.showSymbol = true});
  final String code;
  final String symbol;
  final bool showSymbol;

  static final Map<String, FarmMoney> _cache = {};

  static Future<FarmMoney> load(Session session, Company company) async {
    final hit = _cache[company.farmId];
    if (hit != null) return hit;
    try {
      final j = await session.farmClient.get('/api/Water/farm-settings', query: {'farmId': company.farmId});
      if (j is Map) {
        final m = FarmMoney(
          code: '${j['currencyCode'] ?? 'GHS'}',
          symbol: '${j['currencySymbol'] ?? 'GHC'}',
          showSymbol: j['showCurrencySymbol'] == true,
        );
        return _cache[company.farmId] = m;
      }
    } on ApiException {
      // The defaults, as the web falls back to them.
    }
    return const FarmMoney();
  }

  static void clearCache() => _cache.clear();

  /// "GHS (GHC)", the report header's currency line.
  String get label => '$code ($symbol)';

  /// fmtMoney: two decimals, the symbol when the setting (or [symbol]) asks.
  String call(num? n, {bool? withSymbol}) {
    final v = fixed2(n ?? 0);
    return (withSymbol ?? showSymbol) ? '$symbol $v' : v;
  }

  /// fmtMoneyShort: no decimals.
  String short(num? n, {bool? withSymbol}) {
    final v = fmtNum(n ?? 0, 0);
    return (withSymbol ?? showSymbol) ? '$symbol $v' : v;
  }
}

/// toLocaleString with exactly two decimals: "1,234.50", "-12.00".
String fixed2(num n) {
  final neg = n < 0;
  final s = n.abs().toStringAsFixed(2);
  final parts = s.split('.');
  final whole = parts[0];
  final b = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
    b.write(whole[i]);
  }
  return '${neg ? '-' : ''}$b.${parts[1]}';
}

/// Backend numerics arrive as numbers or numeric strings; normalise once.
num toNum(Object? v) {
  final n = v is num ? v : num.tryParse('${v ?? ''}');
  return n == null || !n.isFinite ? 0 : n;
}

/// The cells' formatting context (the web's FmtCtx). Table cells print money
/// bare; scorecards keep the symbol.
class FmtCtx {
  const FmtCtx(this.moneyFmt, {this.withSymbol = false});
  final FarmMoney moneyFmt;
  final bool withSymbol;

  String money(Object? n) => n == null ? 'N/A' : moneyFmt(toNum(n), withSymbol: withSymbol);
  String number(Object? n) => n == null ? 'N/A' : fmtNum(toNum(n), 2);
  String pct(Object? n) => n == null ? 'N/A' : '${toNum(n).toStringAsFixed(1)}%';
  String date(Object? s) {
    final t = '${s ?? ''}';
    return t.isEmpty ? '—' : (t.length >= 10 ? t.substring(0, 10) : t);
  }

  String text(Object? s) => s == null || '$s'.trim().isEmpty ? '—' : '$s';
}

// ---------------------------------------------------------------- periods

const periodGroups = <(String, List<(String, String)>)>[
  ('Day', [('today', 'Today'), ('yesterday', 'Yesterday')]),
  ('Week', [('thisWeek', 'This Week'), ('lastWeek', 'Last Week'), ('last7', 'Last 7 Days')]),
  ('Month', [('thisMonth', 'This Month'), ('lastMonth', 'Last Month'), ('last30', 'Last 30 Days')]),
  ('Quarter', [('thisQuarter', 'This Quarter'), ('lastQuarter', 'Last Quarter')]),
  ('Year', [('thisYear', 'This Year'), ('lastYear', 'Last Year'), ('ytd', 'Year to Date')]),
  ('Other', [('custom', 'Custom Date Range'), ('allTime', 'All Time')]),
];

String periodLabel(String key) {
  for (final (_, opts) in periodGroups) {
    for (final (k, l) in opts) {
      if (k == key) return l;
    }
  }
  return key;
}

typedef DateRange = ({String from, String to});

DateTime _d(int y, int m, int d) => DateTime(y, m, d);

/// periodToRange: weeks start on Monday; null for custom.
DateRange? periodToRange(String period, [DateTime? today]) {
  final now = today ?? DateTime.now();
  final t = _d(now.year, now.month, now.day);
  final y = t.year, m = t.month;
  DateTime add(DateTime x, int n) => _d(x.year, x.month, x.day + n);
  DateTime weekStart(DateTime x) => add(x, -((x.weekday + 6) % 7));
  DateRange r(DateTime a, DateTime b) => (from: isoDay(a), to: isoDay(b));
  switch (period) {
    case 'today':
      return r(t, t);
    case 'yesterday':
      return r(add(t, -1), add(t, -1));
    case 'thisWeek':
      final s = weekStart(t);
      return r(s, add(s, 6));
    case 'lastWeek':
      final s = add(weekStart(t), -7);
      return r(s, add(s, 6));
    case 'last7':
      return r(add(t, -6), t);
    case 'thisMonth':
      return r(_d(y, m, 1), _d(y, m + 1, 0));
    case 'lastMonth':
      return r(_d(y, m - 1, 1), _d(y, m, 0));
    case 'last30':
      return r(add(t, -29), t);
    case 'thisQuarter':
      final q = (m - 1) ~/ 3;
      return r(_d(y, q * 3 + 1, 1), _d(y, q * 3 + 4, 0));
    case 'lastQuarter':
      var q = (m - 1) ~/ 3 - 1;
      var yy = y;
      if (q < 0) {
        q = 3;
        yy = y - 1;
      }
      return r(_d(yy, q * 3 + 1, 1), _d(yy, q * 3 + 4, 0));
    case 'thisYear':
      return r(_d(y, 1, 1), _d(y, 12, 31));
    case 'lastYear':
      return r(_d(y - 1, 1, 1), _d(y - 1, 12, 31));
    case 'ytd':
      return r(_d(y, 1, 1), t);
    case 'allTime':
      return (from: '2000-01-01', to: isoDay(t));
    default:
      return null;
  }
}

DateRange defaultReportRange([String period = 'last30']) => periodToRange(period)!;

/// rangeToPeriod: the preset a range matches, or "custom".
String rangeToPeriod(String from, String to, [DateTime? today]) {
  for (final (_, opts) in periodGroups) {
    for (final (k, _) in opts) {
      if (k == 'custom') continue;
      final r = periodToRange(k, today);
      if (r != null && r.from == from && r.to == to) return k;
    }
  }
  return 'custom';
}

// ------------------------------------------------------------- vocabulary

const _flowGroupLabels = {
  'OperatingIn': 'Operating income',
  'OperatingOut': 'Operating expense',
  'FinancingIn': 'Capital received',
  'FinancingOut': 'Capital withdrawn',
  'EmployeeLoanOut': 'Employee advance',
  'EmployeeLoanIn': 'Employee advance repaid',
};

String flowGroupLabel(Object? g) => _flowGroupLabels['${g ?? ''}'] ?? '${g ?? ''}';

const _sourceLabels = {
  'Sale': 'Sales',
  'Expense': 'Expenses paid',
  'Payroll': 'Staff wages',
  'RawMaterialPurchase': 'Raw materials',
  'Adjustment': 'Cash account adjustment',
  'LegacyAdjustment': 'Cash adjustment',
  'ExpensePayment': 'Bills paid later',
  'PoultrySupplierPayment': 'Supplier payments',
  'FeedProduction': 'Feed made',
  'FeedProductionReversal': 'Feed production reversed',
  'CustomerPayment': 'Customer payments',
  'DriverReturn': 'Driver returns',
  'OwnerDeposit': 'Owner contribution',
  'Withdrawal': 'Owner draw',
  'DailyClosing': 'Daily closing',
  'Maintenance': 'Maintenance',
  'ReconciliationAdjustment': 'Cash account reconciliation',
  'Transfer': 'Internal transfer',
  'OwnerInjection': 'Owner injection',
  'LoanReceived': 'Loan received',
  'OpeningBalance': 'Opening balance',
  'Correction': 'Correction',
  'OwnerContribution': 'Owner contribution',
  'OwnerDraw': 'Owner draw',
  'LoanRepayment': 'Loan repayment (total paid)',
  'Sales': 'Sales',
  'Supplier payments': 'Supplier payments',
  'Internal transfer': 'Internal transfer',
  'Uncategorised': 'No category set',
  'GuestPayment': 'Guest payments',
  'RestaurantOrder': 'Restaurant / F&B',
  'DepositCollected': 'Guest deposits',
  'DepositRefunded': 'Deposit refunds',
};

const _reasonLabels = {
  'Owner contribution not recorded': 'Owner contribution',
  'Owner draw not recorded': 'Owner draw',
  'Unrecorded income': 'Other income',
  'Unrecorded expense': 'Other spending',
};

String _titleCase(String s) {
  final spaced = s.replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}');
  return spaced.isEmpty ? spaced : spaced[0].toUpperCase() + spaced.substring(1);
}

/// categoryLabel: one vocabulary for cash categories; a farm's own expense
/// categories pass through unchanged.
String categoryLabel(Object? raw) {
  final s = '${raw ?? ''}'.trim();
  if (s.isEmpty) return 'Unclassified';
  return _sourceLabels[s] ?? _reasonLabels[s] ?? (RegExp(r'[a-z][A-Z]').hasMatch(s) ? _titleCase(s) : s);
}

// --------------------------------------------------------------- analysis

typedef Bucket = ({String label, num amount, num? sharePercent, num movements});

/// Bucket list from the API, through categoryLabel, empty ones dropped.
List<Bucket> buckets(Object? list) => [
      if (list is List)
        for (final b in list)
          if (b is Map && toNum(b['amount']) > 0)
            (
              label: categoryLabel(b['label']),
              amount: toNum(b['amount']),
              sharePercent: b['sharePercent'] == null ? null : toNum(b['sharePercent']),
              movements: toNum(b['movements']),
            ),
    ];

typedef AnalysisItem = ({String id, String tone, String title, String detail});

num? pctChange(num now, num before) => before == 0 ? null : ((now - before) / before.abs()) * 100;

String? describeChange(num? pct) {
  if (pct == null) return null;
  final r = (pct.abs() * 10).round() / 10;
  if (r < 0.1) return 'unchanged';
  return '${pct > 0 ? 'up' : 'down'} ${r.toStringAsFixed(1)}%';
}

int? runwayDays(num cashAtHand, num netCashFlow, num daysInPeriod) {
  if (netCashFlow >= 0 || daysInPeriod <= 0 || cashAtHand <= 0) return null;
  final perDay = netCashFlow.abs() / daysInPeriod;
  if (perDay <= 0) return null;
  return (cashAtHand / perDay).floor();
}

num _round2(num n) => (n * 100).round() / 100;

/// buildCashFlowAnalysis, sentence for sentence. [s] is the report summary.
List<AnalysisItem> buildCashFlowAnalysis(Map s, String Function(num) fmt) {
  final moneyIn = toNum(s['moneyIn']), moneyOut = toNum(s['moneyOut']);
  final net = toNum(s['netCashFlow']), cash = toNum(s['cashAtHand']);
  final opIn = toNum(s['operatingIn']), opOut = toNum(s['operatingOut']);
  final finIn = toNum(s['financingIn']), finOut = toNum(s['financingOut']);
  final offIn = toNum(s['offLedgerIn']), offOut = toNum(s['offLedgerOut']);
  final transfers = toNum(s['transferVolume']);
  final days = toNum(s['daysInPeriod']);
  final prevIn = toNum(s['previousMoneyIn']), prevOut = toNum(s['previousMoneyOut']);
  final prevNet = toNum(s['previousNetCashFlow']);
  final ins = buckets(s['moneyInByCategory']), outs = buckets(s['moneyOutByCategory']);
  final out = <AnalysisItem>[];

  if (!(moneyIn > 0 || moneyOut > 0)) {
    return [
      (
        id: 'no-activity',
        tone: 'neutral',
        title: 'No cash moved in this period',
        detail: 'Nothing came in and nothing went out. Widen the date range, or check that sales and expenses are being recorded.',
      ),
    ];
  }

  if (net >= 0) {
    final kept = moneyIn > 0 ? (net / moneyIn) * 100 : 0;
    out.add((
      id: 'net-positive',
      tone: 'good',
      title: 'Cash positive — you kept ${fmt(net)}',
      detail: '${fmt(moneyIn)} came in and ${fmt(moneyOut)} went out, so you held on to ${kept.toStringAsFixed(1)} of every 100 that arrived.',
    ));
  } else {
    out.add((
      id: 'net-negative',
      tone: 'watch',
      title: 'Spent ${fmt(net.abs())} more than came in',
      detail: '${fmt(moneyOut)} went out against ${fmt(moneyIn)} in. The gap was covered by cash already held, so the balance fell rather than the business stopping.',
    ));
  }

  if (opIn + opOut + finIn + finOut > 0) {
    final opNet = opIn - opOut;
    if (opNet >= 0) {
      out.add((
        id: 'operating-self-funding',
        tone: 'good',
        title: 'Trading covered its own costs, with ${fmt(opNet)} left',
        detail: finIn > 0
            ? '${fmt(opIn)} earned against ${fmt(opOut)} spent. ${fmt(finIn)} of capital also came in, but the business did not need it to cover trading.'
            : '${fmt(opIn)} earned against ${fmt(opOut)} spent, with no capital needed.',
      ));
    } else {
      final gap = opNet.abs();
      final covered = finIn >= gap;
      out.add((
        id: 'operating-shortfall',
        tone: 'watch',
        title: 'Trading fell short by ${fmt(gap)}',
        detail: finIn > 0
            ? '${fmt(opIn)} earned against ${fmt(opOut)} spent. ${fmt(finIn)} of capital came in, ${covered ? 'which covered the gap' : 'which did not cover it'} — so ${covered ? 'this period was funded rather than earned' : 'cash already held made up the rest'}.'
            : '${fmt(opIn)} earned against ${fmt(opOut)} spent, and no capital came in — the gap came out of cash already held.',
      ));
    }
  }

  if (finOut > 0) {
    out.add((
      id: 'capital-out',
      tone: 'neutral',
      title: '${fmt(finOut)} taken out as capital',
      detail: 'Owner withdrawals and loan repayments. Counted in money out, but it is not a cost of running the business — trading performance is the operating figures above.',
    ));
  }

  if (outs.isNotEmpty && outs.first.amount > 0 && moneyOut > 0) {
    final top = outs.first;
    final share = top.sharePercent ?? (top.amount / moneyOut) * 100;
    final concentrated = share >= 50 && outs.length >= 3;
    out.add((
      id: 'top-outflow',
      tone: concentrated ? 'watch' : 'neutral',
      title: '${top.label} took ${share.toStringAsFixed(1)}% of spending',
      detail: concentrated
          ? '${fmt(top.amount)} of ${fmt(moneyOut)} went on ${top.label.toLowerCase()} — more than half of everything spent. A price change there moves the whole month.'
          : '${fmt(top.amount)} of ${fmt(moneyOut)}, the largest of ${outs.length} spending categories.',
    ));
  }

  if (ins.isNotEmpty && ins.first.amount > 0 && moneyIn > 0) {
    final top = ins.first;
    final share = top.sharePercent ?? (top.amount / moneyIn) * 100;
    final single = ins.length == 1;
    out.add((
      id: 'top-inflow',
      tone: share >= 80 && !single ? 'watch' : 'neutral',
      title: '${top.label} brought in ${share.toStringAsFixed(1)}% of the money',
      detail: single
          ? 'All ${fmt(top.amount)} of it. Every cedi this period came from one place.'
          : '${fmt(top.amount)} of ${fmt(moneyIn)}${share >= 80 ? ' — most income depends on this one source.' : '.'}',
    ));
  }

  if (prevIn > 0 || prevOut > 0) {
    final inWord = describeChange(pctChange(moneyIn, prevIn));
    final outWord = describeChange(pctChange(moneyOut, prevOut));
    if (inWord != null || outWord != null) {
      final improving = net > prevNet;
      out.add((
        id: 'vs-previous',
        tone: improving ? 'good' : 'watch',
        title: improving ? 'Better than the period before' : 'Worse than the period before',
        detail: '${[if (inWord != null) 'Money in $inWord', if (outWord != null) 'money out $outWord'].join(', ')}'
            '. Net moved from ${fmt(prevNet)} to ${fmt(net)} over the same number of days.',
      ));
    }
  }

  final runway = runwayDays(cash, net, days);
  if (runway != null) {
    final perDay = net.abs() / days;
    out.add((
      id: 'runway',
      tone: runway < 30 ? 'watch' : 'neutral',
      title: 'About $runway days of cash at this rate',
      detail: 'Net spending ran at ${fmt(_round2(perDay))} a day. Against ${fmt(cash)} on hand that is roughly $runway days — a projection from this period alone, not a forecast.',
    ));
  } else if (net > 0 && days > 0) {
    out.add((
      id: 'accumulation',
      tone: 'good',
      title: 'Building cash at ${fmt(_round2(net / days))} a day',
      detail: 'Averaged across ${days.toInt()} days. Cash on hand is ${fmt(cash)}.',
    ));
  }

  final off = offIn + offOut;
  if (off > 0) {
    final share = moneyIn + moneyOut > 0 ? (off / (moneyIn + moneyOut)) * 100 : 0;
    out.add((
      id: 'off-ledger',
      tone: 'neutral',
      title: '${fmt(off)} moved without a cash account',
      detail: '${share.toStringAsFixed(1)}% of all movement — usually owner injections, or expenses paid without picking an account. Counted in the totals above, but in no account balance, so reconciliation will not see it.',
    ));
  }

  if (transfers > 0) {
    out.add((
      id: 'transfers',
      tone: 'neutral',
      title: '${fmt(transfers)} moved between your own accounts',
      detail: 'Excluded from money in and money out — it is the same money in a different place, not income or spending.',
    ));
  }
  return out;
}

/// Keeps math imported for callers that clamp percentages.
double clampPct(num? p) => p == null ? 0 : math.min(100, math.max(0, p.toDouble()));
