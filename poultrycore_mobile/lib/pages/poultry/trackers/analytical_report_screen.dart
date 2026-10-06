import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/buttons.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../reports/report_export.dart';
import 'tracker_logic.dart';
import 'tracker_widgets.dart';

const eggsPerCrate = 30;
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monLong = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November',
  'December',
];
const allTimeFrom = '1970-01-01';
const allTimeTo = '9999-12-31';
const maxDayColumns = 31;

enum RangeMode { week, month, range, all }

DateTime startOfWeek(DateTime d) {
  final x = DateTime(d.year, d.month, d.day);
  return x.subtract(Duration(days: (x.weekday + 6) % 7));
}

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
String fmtShortDay(DateTime d) => '${_monShort[d.month - 1]} ${d.day}';

String fmtMonth(String yyyymm) {
  final p = yyyymm.split('-').map(int.tryParse).toList();
  if (p.length != 2 || p[0] == null || p[1] == null) return yyyymm;
  return '${_monLong[p[1]! - 1]} ${p[0]}';
}

String monthEnd(String yyyymm) {
  final p = yyyymm.split('-').map(int.parse).toList();
  final last = DateTime(p[0], p[1] + 1, 0).day;
  return '$yyyymm-${last.toString().padLeft(2, '0')}';
}

String _ym(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// "GH₵1,234" — the page's hard-coded GHS currency format.
String ghs(num n, [int digits = 0]) {
  final neg = n < 0;
  final s = fmtNum(n.abs(), digits);
  final body = digits > 0 && !s.contains('.') ? '$s.${'0' * digits}' : _padDecimals(s, digits);
  return '${neg ? '-' : ''}GH₵$body';
}

String _padDecimals(String s, int digits) {
  if (digits == 0 || !s.contains('.')) return s;
  final parts = s.split('.');
  return '${parts[0]}.${parts[1].padRight(digits, '0')}';
}

bool _isEggSale(Object? product) => tStr(product).toLowerCase().contains('egg');

/// saleOwed: amountPaid is the truth; the binary paid flag is the fallback.
num saleOwed(Map s) {
  final total = tNum(s['totalAmount']);
  final paid = s['amountPaid'] != null ? tNum(s['amountPaid']) : (s['paid'] == false ? 0 : total);
  return math.max(0, total - paid);
}

/// Saleable eggs from one record: picks less every non-saleable category.
num saleableEggsOf(Map r) {
  final collected = tNum(r['totalProduction']);
  final losses = tNum(r['brokenEggs']) + tNum(r['meatyEggs']) + tNum(r['softEggs']) + tNum(r['lostEggs']);
  return math.max(0, collected - losses);
}

/// "12" or "12 + 7" (crates plus loose eggs).
String formatCrates(num eggs) {
  final n = math.max(0, eggs).toInt();
  final crates = n ~/ eggsPerCrate;
  final loose = n % eggsPerCrate;
  return loose != 0 ? '${loc(crates)} + $loose' : loc(crates);
}

typedef DayCol = ({String key, String label});
typedef DailyRow = ({String key, String name, String? house, List<num> days, num total});
typedef RoomRow = ({String name, num eggs, num losses, num saleable, num sold, num unsold});
typedef SizeRow = ({String size, num eggs, int crates, num avgPrice, num revenue});

/// Every figure on the Analytical Report, for one set of filters. Pure, so the
/// arithmetic is tested on its own (the web computes it in useMemos).
class AnalyticalReport {
  AnalyticalReport({
    required this.flocks,
    required this.houses,
    required this.records,
    required this.sales,
    required this.expenses,
    required this.mode,
    required this.weekStart,
    required this.selectedMonth,
    required this.dateFrom,
    required this.dateTo,
    required this.flockFilter,
    required this.houseFilter,
  }) {
    _compute();
  }

  final List<Map> flocks, houses, records, sales, expenses;
  final RangeMode mode;
  final DateTime weekStart;
  final String selectedMonth, dateFrom, dateTo, flockFilter, houseFilter;

  late final String from, to, label;
  late final List<Map> filteredRecords, filteredSales, filteredExpenses, eligibleFlocks, eggSales;
  late final num totalEggsCollected, totalEggsSold, eggRevenue, totalRevenue, otherRevenue, totalExpenses, netBalance;
  late final num periodSaleableEggs, periodUnsoldEggs, eggsInStock;
  late final List<DayCol> dayColumns;
  late final List<DailyRow> dailyRows;
  late final List<num> dailyDayTotals;
  late final List<RoomRow> roomSummary;
  late final RoomRow roomTotals;
  late final List<Map> expenseRows;
  late final List<SizeRow> salesBySize;
  late final ({num broken, num meaty, num soft, num lost, num total}) eggLoss;
  late final List<({String customer, num amount})> debtors;
  late final num totalDebt;

  Map? _flock(Object? id) => flocks.where((f) => tIntOrNull(f['flockId']) == tIntOrNull(id)).firstOrNull;

  bool inFlockScope(Object? flockId) {
    if (flockFilter != 'ALL' && '${tIntOrNull(flockId)}' != flockFilter) return false;
    if (houseFilter != 'ALL') {
      final f = _flock(flockId);
      if (f == null || '${f['houseId'] ?? ''}' != houseFilter) return false;
    }
    return true;
  }

  static List<String> monthOptions(List<Map> records, List<Map> sales, [DateTime? now]) {
    final set = <String>{_ym(now ?? DateTime.now())};
    for (final r in records) {
      final d = DateTime.tryParse(tStr(r['date']));
      if (d != null) set.add(_ym(d));
    }
    for (final s in sales) {
      final d = DateTime.tryParse(tStr(s['saleDate']));
      if (d != null) set.add(_ym(d));
    }
    return set.toList()..sort((a, b) => b.compareTo(a));
  }

  void _compute() {
    if (mode == RangeMode.all) {
      from = allTimeFrom;
      to = allTimeTo;
      label = 'All time';
    } else if (mode == RangeMode.month) {
      from = '$selectedMonth-01';
      to = monthEnd(selectedMonth);
      label = fmtMonth(selectedMonth);
    } else if (mode == RangeMode.range && dateFrom.isNotEmpty && dateTo.isNotEmpty) {
      from = dateFrom;
      to = dateTo;
      label = '$dateFrom → $dateTo';
    } else {
      from = isoDay(weekStart);
      to = isoDay(addDays(weekStart, 6));
      label = '${fmtShortDay(weekStart)} – ${fmtShortDay(addDays(weekStart, 6))}';
    }

    eligibleFlocks = [for (final f in flocks) if (flockCountsTowardBirdTotals(f)) f];
    bool inRange(String k) => k.compareTo(from) >= 0 && k.compareTo(to) <= 0;

    filteredRecords = [
      for (final r in records)
        if (inRange(localDateKey(r['date'])) && inFlockScope(r['flockId'])) r,
    ];
    filteredSales = [
      for (final s in sales)
        if (inRange(localDateKey(s['saleDate'])) && inFlockScope(s['flockId'])) s,
    ];
    final houseFlockIds = houseFilter == 'ALL'
        ? null
        : {for (final f in flocks) if ('${f['houseId'] ?? ''}' == houseFilter) tIntOrNull(f['flockId'])};
    filteredExpenses = [
      for (final e in expenses)
        if (inRange(localDateKey(e['expenseDate'])) &&
            (flockFilter == 'ALL' || '${tIntOrNull(e['flockId'])}' == flockFilter) &&
            (houseFlockIds == null || (e['flockId'] != null && houseFlockIds.contains(tIntOrNull(e['flockId'])))))
          e,
    ];

    totalEggsCollected = filteredRecords.fold<num>(0, (s, r) => s + tNum(r['totalProduction']));
    eggSales = [for (final s in filteredSales) if (_isEggSale(s['product'])) s];
    totalEggsSold = eggSales.fold<num>(0, (s, x) => s + tNum(x['quantity']));
    eggRevenue = eggSales.fold<num>(0, (s, x) => s + tNum(x['totalAmount']));
    totalRevenue = filteredSales.fold<num>(0, (s, x) => s + tNum(x['totalAmount']));
    otherRevenue = totalRevenue - eggRevenue;
    totalExpenses = filteredExpenses.fold<num>(0, (s, e) => s + tNum(e['amount']));
    netBalance = totalRevenue - totalExpenses;

    periodSaleableEggs = filteredRecords.fold<num>(0, (s, r) => s + saleableEggsOf(r));
    periodUnsoldEggs = periodSaleableEggs - totalEggsSold;
    num collected = 0, sold = 0;
    for (final r in records) {
      if (localDateKey(r['date']).compareTo(to) > 0) continue;
      if (!inFlockScope(r['flockId'])) continue;
      collected += saleableEggsOf(r);
    }
    for (final s in sales) {
      if (!_isEggSale(s['product'])) continue;
      if (localDateKey(s['saleDate']).compareTo(to) > 0) continue;
      if (!inFlockScope(s['flockId'])) continue;
      sold += tNum(s['quantity']);
    }
    eggsInStock = collected - sold;

    // Daily grid: real calendar days, up to 31 columns.
    ({String from, String to})? span;
    if (mode != RangeMode.all) {
      span = (from: from, to: to);
    } else {
      final keys = [for (final r in filteredRecords) localDateKey(r['date'])]..removeWhere((k) => k.isEmpty);
      keys.sort();
      span = keys.isEmpty ? null : (from: keys.first, to: keys.last);
    }
    final cols = <DayCol>[];
    final f0 = span == null ? null : businessDateAsDateTime(span.from);
    final t0 = span == null ? null : businessDateAsDateTime(span.to);
    if (f0 != null && t0 != null && !t0.isBefore(f0)) {
      final days = DateTime.utc(t0.year, t0.month, t0.day).difference(DateTime.utc(f0.year, f0.month, f0.day)).inDays + 1;
      if (days <= maxDayColumns) {
        for (var i = 0; i < days; i++) {
          final d = addDays(f0, i);
          cols.add((key: isoDay(d), label: days <= 7 ? _weekdays[(d.weekday + 6) % 7] : '${d.day}/${d.month}'));
        }
      }
    }
    dayColumns = cols;

    final colIndex = {for (var i = 0; i < cols.length; i++) cols[i].key: i};
    final rows = <String, ({String name, String? house, List<num> days, List<num> total})>{};
    String? houseNameOf(Map? f) {
      if (f == null) return null;
      final h = houses.where((h) => tIntOrNull(h['houseId']) == tIntOrNull(f['houseId'])).firstOrNull;
      return h == null ? null : tStr(h['name'] ?? h['houseName']);
    }

    void ensure(String key, String name, String? house) =>
        rows.putIfAbsent(key, () => (name: name, house: house, days: List<num>.filled(cols.length, 0), total: [0]));
    final visible = flockFilter != 'ALL' ? [for (final f in flocks) if ('${tIntOrNull(f['flockId'])}' == flockFilter) f] : eligibleFlocks;
    for (final f in visible) {
      final n = tStr(f['name']);
      ensure('${tIntOrNull(f['flockId'])}', n.isNotEmpty ? n : 'Flock #${f['flockId']}', houseNameOf(f));
    }
    for (final r in filteredRecords) {
      final eggs = tNum(r['totalProduction']);
      final fid = tIntOrNull(r['flockId']);
      final flock = fid != null ? _flock(fid) : null;
      final key = fid != null ? '$fid' : 'unassigned';
      final fname = tStr(flock?['name']);
      ensure(key, fname.isNotEmpty ? fname : (fid != null ? 'Flock #$fid' : 'Unassigned'), houseNameOf(flock));
      final row = rows[key]!;
      row.total[0] += eggs;
      final i = colIndex[localDateKey(r['date'])];
      if (i != null) row.days[i] += eggs;
    }
    dailyRows = [
      for (final e in rows.entries) (key: e.key, name: e.value.name, house: e.value.house, days: e.value.days, total: e.value.total[0]),
    ];
    dailyDayTotals = [for (var i = 0; i < cols.length; i++) dailyRows.fold<num>(0, (s, r) => s + r.days[i])];

    // Room production summary.
    final houseMap = <int, List<num>>{}; // eggs, losses, saleable, sold
    final houseNames = <int, String>{};
    for (final h in houses) {
      final id = tIntOrNull(h['houseId']) ?? 0;
      houseMap[id] = [0, 0, 0, 0];
      houseNames[id] = tStr(h['name'] ?? h['houseName']);
    }
    final unassigned = <num>[0, 0, 0, 0];
    final flockToHouse = {for (final f in flocks) tIntOrNull(f['flockId']): tIntOrNull(f['houseId'])};
    for (final r in filteredRecords) {
      final eggs = tNum(r['totalProduction']);
      if (eggs <= 0 || r['flockId'] == null) continue;
      final saleable = saleableEggsOf(r);
      final hid = flockToHouse[tIntOrNull(r['flockId'])];
      final row = hid != null && houseMap.containsKey(hid) ? houseMap[hid]! : unassigned;
      row[0] += eggs;
      row[2] += saleable;
      row[1] += eggs - saleable;
    }
    for (final s in filteredSales) {
      if (!_isEggSale(s['product'])) continue;
      final q = tNum(s['quantity']);
      if (q <= 0 || s['flockId'] == null) continue;
      final hid = flockToHouse[tIntOrNull(s['flockId'])];
      (hid != null && houseMap.containsKey(hid) ? houseMap[hid]! : unassigned)[3] += q;
    }
    final room = <RoomRow>[
      for (final e in houseMap.entries)
        if (e.value[0] > 0 || e.value[3] > 0)
          (name: houseNames[e.key]!, eggs: e.value[0], losses: e.value[1], saleable: e.value[2], sold: e.value[3], unsold: e.value[2] - e.value[3]),
      if (unassigned[0] > 0 || unassigned[3] > 0)
        (name: 'Unassigned', eggs: unassigned[0], losses: unassigned[1], saleable: unassigned[2], sold: unassigned[3], unsold: unassigned[2] - unassigned[3]),
    ];
    // Stable sort by eggs, most first.
    final idx = [for (var i = 0; i < room.length; i++) (i, room[i])]
      ..sort((a, b) {
        final c = b.$2.eggs.compareTo(a.$2.eggs);
        return c != 0 ? c : a.$1 - b.$1;
      });
    roomSummary = [for (final e in idx) e.$2];
    roomTotals = roomSummary.fold<RoomRow>(
      (name: 'All rooms', eggs: 0, losses: 0, saleable: 0, sold: 0, unsold: 0),
      (a, r) => (
        name: a.name,
        eggs: a.eggs + r.eggs,
        losses: a.losses + r.losses,
        saleable: a.saleable + r.saleable,
        sold: a.sold + r.sold,
        unsold: a.unsold + r.unsold
      ),
    );

    expenseRows = [...filteredExpenses]..sort((a, b) => tStr(a['expenseDate']).compareTo(tStr(b['expenseDate'])));

    final bySize = <String, List<num>>{}; // eggs, crates, revenue
    for (final s in eggSales) {
      final sz = tStr(s['size']).trim();
      final key = sz.isNotEmpty ? sz : 'Unspecified';
      final eggs = tNum(s['quantity']);
      final cur = bySize.putIfAbsent(key, () => [0, 0, 0]);
      cur[0] += eggs;
      cur[1] += eggs ~/ eggsPerCrate;
      cur[2] += tNum(s['totalAmount']);
    }
    salesBySize = [
      for (final e in bySize.entries)
        (
          size: e.key,
          eggs: e.value[0],
          crates: e.value[1].toInt(),
          avgPrice: e.value[1] != 0 ? e.value[2] / e.value[1] : 0,
          revenue: e.value[2],
        ),
    ]..sort((a, b) => b.revenue.compareTo(a.revenue));

    num broken = 0, meaty = 0, soft = 0, lost = 0;
    for (final r in filteredRecords) {
      broken += tNum(r['brokenEggs']);
      meaty += tNum(r['meatyEggs']);
      soft += tNum(r['softEggs']);
      lost += tNum(r['lostEggs']);
    }
    eggLoss = (broken: broken, meaty: meaty, soft: soft, lost: lost, total: broken + meaty + soft + lost);

    final owed = <String, num>{};
    for (final s in filteredSales) {
      final o = saleOwed(s);
      if (o <= 0) continue;
      final n = tStr(s['customerName']).trim();
      final name = n.isEmpty ? 'Unknown' : n;
      owed[name] = (owed[name] ?? 0) + o;
    }
    debtors = [
      for (final e in owed.entries)
        if (e.value > 0) (customer: e.key, amount: e.value),
    ]..sort((a, b) => b.amount.compareTo(a.amount));
    totalDebt = debtors.fold<num>(0, (s, d) => s + d.amount);
  }
}

/// Poultry → Trackers → Analytical Report, as `app/weekly-report/page.tsx`:
/// a week (Mon–Sun), a month, a custom range or all time, narrowed by flock
/// and room, over production records, sales and expenses; plus the weekly
/// observation notes (FarmObservation, per farm + week). The web's Print
/// becomes a shared PDF in the Reports letterhead.
class AnalyticalReportScreen extends StatefulWidget {
  const AnalyticalReportScreen({super.key, required this.session, required this.company, this.now});
  final Session session;
  final Company company;

  /// "Today", for tests.
  final DateTime? now;

  @override
  State<AnalyticalReportScreen> createState() => _AnalyticalReportScreenState();
}

class _AnalyticalReportScreenState extends State<AnalyticalReportScreen> {
  List<Map> _flocks = [], _houses = [], _records = [], _sales = [], _expenses = [];
  bool _loading = true;
  bool _refreshing = false;
  String _error = '';

  RangeMode _mode = RangeMode.week;
  late DateTime _weekStart = startOfWeek(_now);
  late String _month = _ym(_now);
  String _dateFrom = '', _dateTo = '';
  String _flockFilter = 'ALL';
  String _houseFilter = 'ALL';

  Map? _observation;
  final _notes = TextEditingController();
  bool _obsSaving = false;

  DateTime get _now => widget.now ?? DateTime.now();
  ApiClient get _api => widget.session.farmClient;

  @override
  void initState() {
    super.initState();
    _load();
    _loadObservation();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final userId = widget.session.tokens.userId;
    final farmId = widget.company.farmId;
    if (userId == null || userId.isEmpty || farmId.isEmpty) {
      setState(() {
        _error = 'Farm ID or User ID not found';
        _loading = false;
        _refreshing = false;
      });
      return;
    }
    final q = {'userId': userId, 'farmId': farmId};
    Future<(List<Map>, String?)> safe(String p) async {
      try {
        return (rowsOf(await _api.get(p, query: q)), null);
      } on ApiException catch (e) {
        return (<Map>[], e.message);
      }
    }

    final r = await Future.wait(
        [safe('/api/Flock'), safe('/api/House'), safe('/api/ProductionRecord'), safe('/api/Sale'), safe('/api/Expense')]);
    if (!mounted) return;
    setState(() {
      _flocks = r[0].$1;
      _houses = r[1].$1;
      _records = r[2].$1;
      _error = r[2].$2 == null ? '' : 'Failed to fetch production records: ${r[2].$2}';
      _sales = r[3].$1;
      _expenses = r[4].$1;
      _loading = false;
      _refreshing = false;
    });
  }

  String get _weekKey => isoDay(_weekStart);

  Future<void> _loadObservation() async {
    final key = _weekKey;
    try {
      final res = await _api.get('/api/FarmObservation/by-week',
          query: {'farmId': widget.company.farmId, 'weekStartDate': key});
      if (!mounted || key != _weekKey) return;
      setState(() {
        _observation = res is Map ? res : null;
        _notes.text = tStr(_observation?['notes']);
      });
    } on ApiException {
      if (!mounted || key != _weekKey) return;
      setState(() {
        _observation = null;
        _notes.text = '';
      });
    }
  }

  void _setWeek(DateTime w) {
    setState(() => _weekStart = w);
    _loadObservation();
  }

  Future<void> _saveObservation() async {
    setState(() => _obsSaving = true);
    final key = _weekKey;
    try {
      final res = await _api.post('/api/FarmObservation', body: {
        'farmId': widget.company.farmId,
        'userId': widget.session.tokens.userId,
        'weekStartDate': key,
        'notes': _notes.text.trim().isNotEmpty ? _notes.text : null,
      });
      if (!mounted) return;
      setState(() => _observation = res is Map ? res : _observation);
      trackerToast(context, 'Observations saved', description: 'Week of $key');
    } on ApiException catch (e) {
      if (mounted) {
        trackerToast(context, 'Save failed', description: e.message.isNotEmpty ? e.message : 'Try again.', error: true);
      }
    }
    if (mounted) setState(() => _obsSaving = false);
  }

  AnalyticalReport get _report => AnalyticalReport(
        flocks: _flocks,
        houses: _houses,
        records: _records,
        sales: _sales,
        expenses: _expenses,
        mode: _mode,
        weekStart: _weekStart,
        selectedMonth: _month,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        flockFilter: _flockFilter,
        houseFilter: _houseFilter,
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/weekly-report');
    final rep = _report;
    return Scaffold(
      appBar: AppBar(
        leading: lead.leading,
        leadingWidth: lead.width,
        title: const Text('Analytical Report'),
        actions: [
          RefreshAction(
              busy: _refreshing || _loading,
              onPressed: () {
                setState(() => _refreshing = true);
                _load();
              }),
          IconButton(
            tooltip: 'Print',
            icon: const Icon(Icons.print_outlined),
            onPressed: _loading ? null : () => ReportExport.sharePdf(_document(rep)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            TrackerHeader(
              icon: Icons.insert_chart_outlined,
              iconBg: TColors.emerald100,
              iconFg: TColors.emerald700,
              title: 'Analytical Report',
              blurbSpans: [
                t('Showing '),
                b(rep.label),
                t('. All totals update automatically based on the selected period.'),
              ],
              session: widget.session,
              company: widget.company,
            ),
            const SizedBox(height: 16),
            _filters(rep),
            const SizedBox(height: 16),
            if (_error.isNotEmpty) ...[TrackerBanner.error(_error), const SizedBox(height: 12)],
            if (_loading) const TrackerLoading('Loading report…') else ..._sections(rep),
          ],
        ),
      ),
    );
  }

  Widget _filters(AnalyticalReport rep) {
    final months = AnalyticalReport.monthOptions(_records, _sales, _now);
    final showReset = _mode != RangeMode.week || _flockFilter != 'ALL' || _houseFilter != 'ALL';
    return TCard(
      title: 'Filters',
      description: 'Pick a week, a month, a custom range, or all time.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<RangeMode>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: RangeMode.week, label: Text('Week')),
              ButtonSegment(value: RangeMode.month, label: Text('Month')),
              ButtonSegment(value: RangeMode.range, label: Text('Custom range')),
              ButtonSegment(value: RangeMode.all, label: Text('All time')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 10),
          if (_mode == RangeMode.week)
            Row(children: [
              IconButton.outlined(
                tooltip: 'Previous week',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _setWeek(addDays(_weekStart, -7)),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  decoration: BoxDecoration(
                    color: TColors.slate50,
                    border: Border.all(color: TColors.slate200),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.calendar_today_outlined, size: 14, color: TColors.slate500),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('${fmtShortDay(_weekStart)} – ${fmtShortDay(addDays(_weekStart, 6))}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate700)),
                    ),
                  ]),
                ),
              ),
              IconButton.outlined(
                tooltip: 'Next week',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _setWeek(addDays(_weekStart, 7)),
              ),
            ]),
          if (_mode == RangeMode.month)
            AppSelect<String>(
              value: months.contains(_month) ? _month : null,
              hintText: 'Month',
              items: [for (final m in months) AppSelectItem(value: m, label: fmtMonth(m))],
              onChanged: (v) => setState(() => _month = v ?? _month),
            ),
          if (_mode == RangeMode.range)
            filterRow([
              FilterDate(value: _dateFrom, hint: 'From', onChanged: (v) => setState(() => _dateFrom = v)),
              FilterDate(value: _dateTo, hint: 'To', onChanged: (v) => setState(() => _dateTo = v)),
            ]),
          if (_mode == RangeMode.all)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: TColors.emerald50,
                border: Border.all(color: TColors.emerald200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Showing every record ever logged for this farm.',
                  style: TextStyle(fontSize: 13, color: TColors.emerald800)),
            ),
          const SizedBox(height: 10),
          AppSelect<String>(
            value: _flockFilter,
            hintText: 'Flock',
            items: [
              const AppSelectItem(value: 'ALL', label: 'All flocks'),
              for (final f in rep.eligibleFlocks)
                AppSelectItem(
                    value: '${tIntOrNull(f['flockId'])}',
                    label: tStr(f['name']).isNotEmpty ? tStr(f['name']) : 'Flock #${f['flockId']}'),
            ],
            onChanged: (v) => setState(() => _flockFilter = v ?? 'ALL'),
          ),
          const SizedBox(height: 8),
          AppSelect<String>(
            value: _houseFilter,
            hintText: 'Room / House',
            items: [
              const AppSelectItem(value: 'ALL', label: 'All rooms'),
              for (final h in _houses)
                AppSelectItem(value: '${tIntOrNull(h['houseId'])}', label: tStr(h['name'] ?? h['houseName'])),
            ],
            onChanged: (v) => setState(() => _houseFilter = v ?? 'ALL'),
          ),
          if (showReset)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _mode = RangeMode.week;
                    _dateFrom = '';
                    _dateTo = '';
                    _flockFilter = 'ALL';
                    _houseFilter = 'ALL';
                  });
                  _setWeek(startOfWeek(_now));
                },
                child: const Text('Reset filters'),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _sections(AnalyticalReport r) {
    const gap = SizedBox(height: 16);
    final stockHint =
        'Saleable eggs on hand as at ${r.to == allTimeTo ? 'today' : r.to}. Excludes egg-tracker adjustments.';
    return [
      TileGrid(boxed: true, [
        TileData('Total Eggs Collected', loc(r.totalEggsCollected), color: TColors.emerald700),
        TileData('Total Eggs Sold', loc(r.totalEggsSold), color: TColors.sky700),
        TileData('Total Revenue', ghs(r.totalRevenue), color: TColors.violet700),
        TileData('Total Expenses', ghs(r.totalExpenses), color: TColors.amber700),
        TileData('Eggs in Stock', loc(r.eggsInStock),
            color: r.eggsInStock >= 0 ? TColors.slate800 : TColors.rose700, sub: stockHint),
        TileData('Net Balance', ghs(r.netBalance), color: r.netBalance >= 0 ? TColors.emerald700 : TColors.rose700),
      ]),
      gap,
      _daily(r),
      gap,
      _rooms(r),
      gap,
      _salesSummary(r),
      gap,
      _financial(r),
      gap,
      _expenditure(r),
      gap,
      _debtors(r),
      gap,
      _bySize(r),
      gap,
      _loss(r),
      gap,
      _observations(),
    ];
  }

  Widget _daily(AnalyticalReport r) {
    final cols = r.dayColumns;
    return TCard(
      title: 'Daily Egg Collection',
      description:
          'Eggs collected per flock, one column per day in the selected period. Crates show as whole crates of $eggsPerCrate plus any loose eggs.'
          '${cols.isEmpty && r.filteredRecords.isNotEmpty ? ' The period is longer than $maxDayColumns days, so only period totals are shown.' : ''}',
      child: TrackerTable(
        emptyText: 'No flocks match the current filters.',
        columns: [
          const TCol('Room / Flock', width: 140),
          for (final c in cols) TCol(c.label, right: true, width: 56),
          const TCol('Total', right: true, width: 80),
          const TCol('Crates', right: true, width: 90),
        ],
        rows: [
          for (final row in r.dailyRows)
            [
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(row.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                if (row.house != null) Text(row.house!, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
              ]),
              for (final n in row.days) cellText(n != 0 ? loc(n) : '—'),
              cellText(loc(row.total), bold: true),
              cellText(formatCrates(row.total), color: TColors.slate600),
            ],
        ],
        footer: r.dailyRows.isEmpty
            ? null
            : [
                cellText('All flocks', bold: true),
                for (final n in r.dailyDayTotals) cellText(n != 0 ? loc(n) : '—', bold: true),
                cellText(loc(r.totalEggsCollected), bold: true),
                cellText(formatCrates(r.totalEggsCollected), color: TColors.slate600, bold: true),
              ],
      ),
    );
  }

  Widget _rooms(AnalyticalReport r) {
    final tt = r.roomTotals;
    return TCard(
      title: 'Room Production Summary',
      description:
          'Per room, for the selected period only. Saleable = collected − broken, meaty, soft and lost eggs. Unsold = saleable − sold, and goes negative when a room’s sales drew on stock collected before this period.',
      child: TrackerTable(
        emptyText: 'No room data for this period.',
        columns: const [
          TCol('Room', width: 120),
          TCol('Eggs Collected', right: true, width: 110),
          TCol('Crates (+ loose)', right: true, width: 120),
          TCol('Losses', right: true, width: 80),
          TCol('Saleable', right: true, width: 90),
          TCol('Sold', right: true, width: 80),
          TCol('Unsold', right: true, width: 80),
        ],
        rows: [
          for (final x in r.roomSummary)
            [
              cellText(x.name, bold: true),
              cellText(loc(x.eggs)),
              cellText(formatCrates(x.eggs), color: TColors.slate600),
              cellText(x.losses != 0 ? loc(x.losses) : '—', color: TColors.rose700),
              cellText(loc(x.saleable)),
              cellText(loc(x.sold)),
              cellText(loc(x.unsold), bold: true, color: x.unsold < 0 ? TColors.rose700 : null),
            ],
        ],
        footer: r.roomSummary.isEmpty
            ? null
            : [
                cellText('All rooms', bold: true),
                cellText(loc(tt.eggs), bold: true),
                cellText(formatCrates(tt.eggs), color: TColors.slate600, bold: true),
                cellText(tt.losses != 0 ? loc(tt.losses) : '—', color: TColors.rose700, bold: true),
                cellText(loc(tt.saleable), bold: true),
                cellText(loc(tt.sold), bold: true),
                cellText(loc(tt.unsold), bold: true, color: tt.unsold < 0 ? TColors.rose700 : null),
              ],
      ),
    );
  }

  Widget _dl(List<(Widget, Widget)> rows, {int totalFrom = -1}) => Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: EdgeInsets.only(top: i == totalFrom ? 8 : 0, bottom: 10),
              decoration: i == totalFrom
                  ? const BoxDecoration(border: Border(top: BorderSide(color: TColors.slate200)))
                  : null,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: rows[i].$1),
                rows[i].$2,
              ]),
            ),
        ],
      );

  Text _dt(String s, {bool strong = false}) => Text(s,
      style: TextStyle(
          fontSize: 13, color: strong ? TColors.slate900 : TColors.slate600, fontWeight: strong ? FontWeight.w600 : null));
  Text _dd(String s, {Color? color, bool bold = false}) => Text(s,
      style: TextStyle(fontSize: 13, color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w600));

  Widget _salesSummary(AnalyticalReport r) => TCard(
        title: 'Sales Summary',
        description:
            'Egg volumes for the period, with revenue split into egg and non-egg sales. Crates read as whole crates of $eggsPerCrate plus loose eggs.',
        child: _dl([
          (_dt('Total eggs sold'), _dd(loc(r.totalEggsSold))),
          (_dt('Total crates sold'), _dd(formatCrates(r.totalEggsSold))),
          (_dt('Crates collected'), _dd(formatCrates(r.totalEggsCollected))),
          (_dt('Saleable eggs collected'), _dd(loc(r.periodSaleableEggs))),
          (
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _dt('Unsold this period'),
              if (r.periodUnsoldEggs < 0)
                const Text('sold more than collected — drawn from earlier stock',
                    style: TextStyle(fontSize: 11, color: TColors.slate400)),
            ]),
            _dd(loc(r.periodUnsoldEggs), color: r.periodUnsoldEggs < 0 ? TColors.rose700 : null)
          ),
          (_dt('Egg sales revenue'), _dd(ghs(r.eggRevenue))),
          (_dt('Other sales revenue'), _dd(ghs(r.otherRevenue))),
          (_dt('Total revenue', strong: true), _dd(ghs(r.totalRevenue), color: TColors.emerald700, bold: true)),
        ], totalFrom: 7),
      );

  Widget _financial(AnalyticalReport r) => TCard(
        title: 'Financial Summary',
        description: 'Balance = Income − Expenditure. Income covers every sale in the period, not just eggs.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dl([
              (_dt('Income (all sales)'), _dd(ghs(r.totalRevenue), color: TColors.emerald700)),
              (_dt('Expenditure'), _dd(ghs(r.totalExpenses), color: TColors.rose700)),
              (
                _dt('Balance', strong: true),
                _dd(ghs(r.netBalance), color: r.netBalance >= 0 ? TColors.emerald700 : TColors.rose700, bold: true)
              ),
            ], totalFrom: 2),
            AppBadge(
              label: r.netBalance >= 0 ? 'Profit for the period' : 'Loss for the period',
              variant: r.netBalance >= 0 ? BadgeVariant.primary : BadgeVariant.destructive,
            ),
          ],
        ),
      );

  Widget _expenditure(AnalyticalReport r) => TCard(
        title: 'Expenditure',
        description: 'Every expense in the selected period.',
        child: TrackerTable(
          emptyText: 'No expenses in this period.',
          columns: const [
            TCol('Date', width: 100),
            TCol('Item', width: 170),
            TCol('Category', width: 120),
            TCol('Price', right: true, width: 110),
          ],
          rows: [
            for (final e in r.expenseRows)
              [
                Text(localDateKey(e['expenseDate']), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                cellText(tStr(e['description']).isNotEmpty ? tStr(e['description']) : '—', bold: true),
                cellText(tStr(e['category']).isNotEmpty ? tStr(e['category']) : '—', color: TColors.slate600),
                cellText(ghs(tNum(e['amount']), 2)),
              ],
          ],
          footer: r.expenseRows.isEmpty
              ? null
              : [
                  const SizedBox(),
                  const SizedBox(),
                  cellText('Total Expenditure', bold: true),
                  cellText(ghs(r.totalExpenses, 2), color: TColors.rose700, bold: true),
                ],
        ),
      );

  Widget _debtors(AnalyticalReport r) => TCard(
        title: 'Debtors',
        description:
            'Customers with an outstanding balance on sales in the selected period. Partial payments are netted off, so a part-paid sale shows only the remainder. Record payments on the Sales page to clear.',
        child: TrackerTable(
          emptyText: 'No outstanding debts in this period.',
          columns: const [TCol('Customer', width: 190), TCol('Amount Owed', right: true, width: 130)],
          rows: [
            for (final d in r.debtors)
              [cellText(d.customer, bold: true), cellText(ghs(d.amount, 2), color: TColors.amber800, bold: true)],
          ],
          footer: r.debtors.isEmpty
              ? null
              : [cellText('Total Outstanding', bold: true), cellText(ghs(r.totalDebt, 2), color: TColors.amber900, bold: true)],
        ),
      );

  Widget _bySize(AnalyticalReport r) {
    final crates = r.salesBySize.fold<int>(0, (s, x) => s + x.crates);
    final eggs = r.salesBySize.fold<num>(0, (s, x) => s + x.eggs);
    final rev = r.salesBySize.fold<num>(0, (s, x) => s + x.revenue);
    return TCard(
      title: 'Egg Sales by Size',
      description:
          'Grouped by the Sale.size field (added by migration 018). Sales without a size appear as “Unspecified”. Egg sales are priced per crate of $eggsPerCrate, so the average price is revenue ÷ crates.',
      child: TrackerTable(
        emptyText: 'No egg sales in this period.',
        columns: const [
          TCol('Size', width: 110),
          TCol('Crates', right: true, width: 80),
          TCol('Eggs', right: true, width: 80),
          TCol('Avg Price / Crate', right: true, width: 130),
          TCol('Total', right: true, width: 110),
        ],
        rows: [
          for (final s in r.salesBySize)
            [
              cellText(s.size, bold: true),
              cellText(loc(s.crates)),
              cellText(loc(s.eggs), color: TColors.slate600),
              cellText(ghs(s.avgPrice, 2), color: TColors.slate600),
              cellText(ghs(s.revenue, 2), color: TColors.emerald700, bold: true),
            ],
        ],
        footer: r.salesBySize.isEmpty
            ? null
            : [
                cellText('Total', bold: true),
                cellText(loc(crates), bold: true),
                cellText(loc(eggs), color: TColors.slate600, bold: true),
                const SizedBox(),
                cellText(ghs(rev, 2), color: TColors.emerald800, bold: true),
              ],
      ),
    );
  }

  Widget _loss(AnalyticalReport r) {
    Widget stat(String label, num v, Color fg, Color bg, Color border) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: fg.withValues(alpha: .8))),
            Text(loc(v), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: fg)),
          ]),
        );
    final l = r.eggLoss;
    return TCard(
      title: 'Egg Loss Tracking',
      description:
          'Totals across production records in the selected period. All four categories are deducted from collected eggs to give the saleable figure used by Eggs in Stock. New loss fields (Meaty / Soft / Lost) require entries logged via the production-record form to populate.',
      child: Column(children: [
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 10) / 2;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            SizedBox(width: w, child: stat('Broken', l.broken, TColors.rose700, TColors.rose50, TColors.rose200)),
            SizedBox(width: w, child: stat('Meaty', l.meaty, TColors.amber700, TColors.amber50, TColors.amber200)),
            SizedBox(width: w, child: stat('Soft', l.soft, TColors.violet700, TColors.violet50, TColors.violet200)),
            SizedBox(width: w, child: stat('Lost', l.lost, TColors.slate700, TColors.slate50, TColors.slate200)),
          ]);
        }),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 10),
        Row(children: [
          const Expanded(
              child: Text('Total eggs lost',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColors.slate700))),
          Text(loc(l.total), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: TColors.rose700)),
        ]),
      ]),
    );
  }

  Widget _observations() {
    final updated = tStr(_observation?['updatedAt']);
    final updatedAt = DateTime.tryParse(updated)?.toLocal();
    return TCard(
      title: 'Observations / Notes',
      descriptionSpans: [
        t('Free-text notes for week of '),
        TextSpan(
            text: '${fmtShortDay(_weekStart)} – ${fmtShortDay(addDays(_weekStart, 6))}',
            style: const TextStyle(fontWeight: FontWeight.w500)),
        t('. Stored per (farm, week) regardless of the filter mode above.'),
        if (updatedAt != null)
          TextSpan(
            text: '  Last saved ${formatShortDate(isoDay(updatedAt))}, '
                '${updatedAt.hour.toString().padLeft(2, '0')}:${updatedAt.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 11, color: TColors.slate400),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppInput(
            controller: _notes,
            minLines: 6,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
            hintText: 'Eggs remaining for the week\nBirds remaining\nFeed purchases\nFeed debts\nMoney brought home',
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: _obsSaving ? 'Saving…' : 'Save observations',
              onPressed: _obsSaving ? null : _saveObservation,
            ),
          ),
        ],
      ),
    );
  }

  /// The printable report: the same sections as the page, in the Reports
  /// letterhead (the web prints the page itself).
  ReportDocument _document(AnalyticalReport r) {
    final l = r.eggLoss;
    return ReportDocument(
      title: 'Analytical Report',
      filename: 'analytical-report',
      farmName: widget.company.name,
      fromDate: r.from == allTimeFrom ? null : r.from,
      toDate: r.to == allTimeTo ? null : r.to,
      currencyLabel: 'GHS',
      filters: [
        ('Period', r.label),
        if (_flockFilter != 'ALL')
          ('Flock', tStr(_flocks.where((f) => '${tIntOrNull(f['flockId'])}' == _flockFilter).firstOrNull?['name'])),
        if (_houseFilter != 'ALL')
          ('Room', tStr(_houses.where((h) => '${tIntOrNull(h['houseId'])}' == _houseFilter).firstOrNull?['name'])),
      ],
      cards: [
        (label: 'Total Eggs Collected', value: loc(r.totalEggsCollected), accent: 'green', note: null),
        (label: 'Total Eggs Sold', value: loc(r.totalEggsSold), accent: 'indigo', note: null),
        (label: 'Total Revenue', value: ghs(r.totalRevenue), accent: 'indigo', note: null),
        (label: 'Total Expenses', value: ghs(r.totalExpenses), accent: 'rose', note: null),
        (label: 'Eggs in Stock', value: loc(r.eggsInStock), accent: r.eggsInStock >= 0 ? null : 'rose', note: null),
        (label: 'Net Balance', value: ghs(r.netBalance), accent: r.netBalance >= 0 ? 'green' : 'rose', note: null),
      ],
      sections: [
        ReportSection(
          heading: 'Daily Egg Collection',
          columns: [
            const ReportColumn('Room / Flock'),
            for (final c in r.dayColumns) ReportColumn(c.label, right: true),
            const ReportColumn('Total', right: true),
            const ReportColumn('Crates', right: true),
          ],
          rows: [
            for (final row in r.dailyRows)
              [
                row.house != null ? '${row.name} (${row.house})' : row.name,
                for (final n in row.days) n != 0 ? loc(n) : '-',
                loc(row.total),
                formatCrates(row.total),
              ],
          ],
          totals: r.dailyRows.isEmpty
              ? null
              : [
                  'All flocks',
                  for (final n in r.dailyDayTotals) n != 0 ? loc(n) : '-',
                  loc(r.totalEggsCollected),
                  formatCrates(r.totalEggsCollected),
                ],
        ),
        ReportSection(
          heading: 'Room Production Summary',
          columns: const [
            ReportColumn('Room'),
            ReportColumn('Eggs Collected', right: true),
            ReportColumn('Crates (+ loose)', right: true),
            ReportColumn('Losses', right: true),
            ReportColumn('Saleable', right: true),
            ReportColumn('Sold', right: true),
            ReportColumn('Unsold', right: true),
          ],
          rows: [
            for (final x in r.roomSummary)
              [x.name, loc(x.eggs), formatCrates(x.eggs), x.losses != 0 ? loc(x.losses) : '-', loc(x.saleable), loc(x.sold), loc(x.unsold)],
          ],
          totals: r.roomSummary.isEmpty
              ? null
              : [
                  'All rooms',
                  loc(r.roomTotals.eggs),
                  formatCrates(r.roomTotals.eggs),
                  r.roomTotals.losses != 0 ? loc(r.roomTotals.losses) : '-',
                  loc(r.roomTotals.saleable),
                  loc(r.roomTotals.sold),
                  loc(r.roomTotals.unsold),
                ],
        ),
        ReportSection(
          heading: 'Sales Summary',
          columns: const [ReportColumn('Figure'), ReportColumn('Value', right: true)],
          rows: [
            ['Total eggs sold', loc(r.totalEggsSold)],
            ['Total crates sold', formatCrates(r.totalEggsSold)],
            ['Crates collected', formatCrates(r.totalEggsCollected)],
            ['Saleable eggs collected', loc(r.periodSaleableEggs)],
            ['Unsold this period', loc(r.periodUnsoldEggs)],
            ['Egg sales revenue', ghs(r.eggRevenue)],
            ['Other sales revenue', ghs(r.otherRevenue)],
          ],
          totals: ['Total revenue', ghs(r.totalRevenue)],
        ),
        ReportSection(
          heading: 'Financial Summary',
          columns: const [ReportColumn('Figure'), ReportColumn('Value', right: true)],
          rows: [
            ['Income (all sales)', ghs(r.totalRevenue)],
            ['Expenditure', ghs(r.totalExpenses)],
          ],
          totals: ['Balance (${r.netBalance >= 0 ? 'profit' : 'loss'} for the period)', ghs(r.netBalance)],
        ),
        ReportSection(
          heading: 'Expenditure',
          columns: const [ReportColumn('Date'), ReportColumn('Item'), ReportColumn('Category'), ReportColumn('Price', right: true)],
          rows: [
            for (final e in r.expenseRows)
              [localDateKey(e['expenseDate']), tStr(e['description']).isEmpty ? '-' : tStr(e['description']), tStr(e['category']).isEmpty ? '-' : tStr(e['category']), ghs(tNum(e['amount']), 2)],
          ],
          totals: r.expenseRows.isEmpty ? null : ['', '', 'Total Expenditure', ghs(r.totalExpenses, 2)],
        ),
        ReportSection(
          heading: 'Debtors',
          columns: const [ReportColumn('Customer'), ReportColumn('Amount Owed', right: true)],
          rows: [for (final d in r.debtors) [d.customer, ghs(d.amount, 2)]],
          totals: r.debtors.isEmpty ? null : ['Total Outstanding', ghs(r.totalDebt, 2)],
        ),
        ReportSection(
          heading: 'Egg Sales by Size',
          columns: const [
            ReportColumn('Size'),
            ReportColumn('Crates', right: true),
            ReportColumn('Eggs', right: true),
            ReportColumn('Avg Price / Crate', right: true),
            ReportColumn('Total', right: true),
          ],
          rows: [
            for (final s in r.salesBySize) [s.size, loc(s.crates), loc(s.eggs), ghs(s.avgPrice, 2), ghs(s.revenue, 2)],
          ],
        ),
        ReportSection(
          heading: 'Egg Loss Tracking',
          columns: const [ReportColumn('Category'), ReportColumn('Eggs', right: true)],
          rows: [
            ['Broken', loc(l.broken)],
            ['Meaty', loc(l.meaty)],
            ['Soft', loc(l.soft)],
            ['Lost', loc(l.lost)],
          ],
          totals: ['Total eggs lost', loc(l.total)],
        ),
      ],
      notes: [
        if (_notes.text.trim().isNotEmpty)
          'Observations (week of ${fmtShortDay(_weekStart)} - ${fmtShortDay(addDays(_weekStart, 6))}): ${_notes.text.trim()}',
      ],
    );
  }
}
