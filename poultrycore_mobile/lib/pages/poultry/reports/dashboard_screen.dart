import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/buttons.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../lookup_loader.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import 'poultry_report_screen.dart';
import 'report_export.dart';
import 'report_format.dart';
import 'report_widgets.dart';
import 'reports_catalog_screen.dart';

/// production | financial | daily | insights
const dashboardViewMeta = {
  'production': (title: 'Production', description: 'Egg production trends, collection times and flock metrics.'),
  'financial': (title: 'Financial', description: 'Revenue, expenses and net profit / loss.'),
  'daily': (title: 'Daily Report', description: 'Daily eggs vs expenses, best and worst days.'),
  'insights': (title: 'More Reports', description: 'Sales by product, expense categories and flock performance.'),
};

String dashboardFilename(String view) => 'poultry-${view == 'insights' ? 'more-reports' : view}';

const _shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// date-fns "MMM d" and "MMM d, yyyy".
String _mmmd(String key) {
  final p = key.split('-');
  return '${_shortMonths[int.parse(p[1]) - 1]} ${int.parse(p[2])}';
}

String _mmmdy(String key) => '${_mmmd(key)}, ${key.substring(0, 4)}';

/// toLocaleDateString, as the Financial table's date column.
String _localeDate(String key) {
  final p = key.split('-');
  return '${int.parse(p[2])}/${int.parse(p[1])}/${p[0]}';
}

String _key(Object? v) => toBusinessDate(v) ?? '';

num _num(Object? v) => toNum(v);
String _loc(num n) => fmtNum(n, 3);

/// getBirdsLeftFromRecord.
num birdsLeftFromRecord(Map? r) {
  if (r == null) return 0;
  final birds = _num(r['noOfBirds']), left = _num(r['noOfBirdsLeft']), mort = _num(r['mortality']);
  if (birds <= 0) return left < 0 ? 0 : left;
  final sameDay = birds - mort < 0 ? 0 : birds - mort;
  if (mort > 0 && left >= birds) return sameDay < birds ? sameDay : birds;
  final v = left < birds ? left : birds;
  return v < 0 ? 0 : v;
}

/// getLatestRecordForFlock: newest date, then newest update, then highest id.
Map? latestRecordForFlock(List<Map> records, int flockId) {
  final mine = [for (final r in records) if (_num(r['flockId']).toInt() == flockId && r['flockId'] != null) r];
  if (mine.isEmpty) return null;
  int ts(Object? v) => DateTime.tryParse('${v ?? ''}')?.millisecondsSinceEpoch ?? 0;
  mine.sort((a, b) {
    final d = ts(b['date']) - ts(a['date']);
    if (d != 0) return d;
    final u = ts(b['updatedAt']) - ts(a['updatedAt']);
    if (u != 0) return u;
    return _num(b['id']).compareTo(_num(a['id']));
  });
  return mine.first;
}

num birdsLeftForFlock(List<Map> records, int flockId) => birdsLeftFromRecord(latestRecordForFlock(records, flockId));

num sumLatestBirdsLeftByFlock(List<Map> records) {
  final ids = {for (final r in records) if (r['flockId'] != null) _num(r['flockId']).toInt()};
  return ids.fold<num>(0, (t, id) => t + birdsLeftForFlock(records, id));
}

/// usePoultryDashboardData: the four lists, the filters, and every metric.
class DashboardData {
  List<Map> records = [], sales = [], expenses = [], flocks = [];
  bool loading = true;
  String dateFrom = '', dateTo = '', selectedFlock = 'ALL', search = '';
  FarmMoney money = const FarmMoney();
  Duration offset = Duration.zero;

  bool _inRange(Object? v) {
    final k = _key(v);
    if (dateFrom.isNotEmpty && (k.isEmpty || k.compareTo(dateFrom) < 0)) return false;
    if (dateTo.isNotEmpty && (k.isEmpty || k.compareTo(dateTo) > 0)) return false;
    return true;
  }

  bool _has(Map m, List<String> keys) {
    final q = search.trim().toLowerCase();
    return q.isEmpty || keys.any((k) => '${m[k] ?? ''}'.toLowerCase().contains(q));
  }

  int? get _flockId => selectedFlock == 'ALL' ? null : int.tryParse(selectedFlock);

  List<Map> get filteredRecords => [
        for (final r in records)
          if (_inRange(r['date']) && (_flockId == null || _num(r['flockId']).toInt() == _flockId) && _has(r, ['flockName', 'medication'])) r,
      ];

  List<Map> get filteredSales => [
        for (final s in sales)
          if (_inRange(s['saleDate']) && (_flockId == null || _num(s['flockId']).toInt() == _flockId) && _has(s, ['product', 'customerName'])) s,
      ];

  List<Map> get filteredExpenses => [
        for (final e in expenses)
          if (_inRange(e['expenseDate'] ?? e['expense_date']) && _has(e, ['description', 'category'])) e,
      ];

  /// A production record's "17 Sep 2026, 11:56": its business date and the
  /// time it was entered, on the company's clock.
  String fmtDateTime(Map r) {
    final k = _key(r['date']);
    if (k.isEmpty) return '';
    final p = k.split('-');
    final date = '${int.parse(p[2])} ${_shortMonths[int.parse(p[1]) - 1]} ${p[0]}';
    for (final c in ['createdDate', 'createdAt', 'dateCreated', 'createdOn']) {
      final v = r[c];
      if (v is String && v.trim().isNotEmpty) {
        final full = fmtInstant(v, offset);
        final at = full.lastIndexOf(', ');
        if (at > 0) return '$date, ${full.substring(at + 2)}';
      }
    }
    return date;
  }

  void clear() {
    dateFrom = '';
    dateTo = '';
    selectedFlock = 'ALL';
    search = '';
  }

  static Future<DashboardData> load(Session session, Company company) async {
    final d = DashboardData();
    final q = {'userId': session.tokens.userId ?? '', 'farmId': company.farmId};
    Future<List<Map>> list(String path) async {
      try {
        return [for (final r in LookupLoader.rowsIn(await session.farmClient.get(path, query: q))) if (r is Map) r];
      } on ApiException {
        return [];
      }
    }

    final r = await Future.wait([
      list('/api/ProductionRecord'),
      list('/api/Sale'),
      list('/api/Expense'),
      list('/api/Flock'),
    ]);
    d
      ..records = r[0]
      ..sales = r[1]
      ..expenses = r[2]
      ..flocks = r[3]
      ..money = await FarmMoney.load(session, company)
      ..offset = (await CompanyClock.load(session, company)).offset
      ..loading = false;
    return d;
  }
}

/// One table on a dashboard view.
class DashTable {
  const DashTable({required this.title, this.description, required this.columns, required this.rows, this.totals, this.cellColor});
  final String title;
  final String? description;
  final List<ReportColumn> columns;
  final List<List<String>> rows;
  final List<String>? totals;
  final Color? Function(List<String> row, int col)? cellColor;
}

typedef DashContent = ({List<SummaryCardData> cards, List<DashTable> tables});

DashContent buildDashboardContent(String view, DashboardData d) {
  final m = d.money;
  final recs = d.filteredRecords;
  final sales = d.filteredSales;
  final exps = d.filteredExpenses;
  num totalEggs = recs.fold<num>(0, (s, r) => s + _num(r['totalProduction']));
  final crates = totalEggs ~/ 30;
  final loose = totalEggs.toInt() % 30;
  final revenue = sales.fold<num>(0, (s, x) => s + _num(x['totalAmount']));
  // Capital and deferred inventory purchases are not this period's expense.
  final expensesAmount = exps
      .where((x) => x['plSection'] == null || ('${x['plSection']}'.isNotEmpty && x['plSection'] != 'Excluded'))
      .fold<num>(0, (s, x) => s + _num(x['amount']));
  final net = revenue - expensesAmount;

  switch (view) {
    case 'production':
      final avg = recs.isEmpty ? 0 : (totalEggs / recs.length).round();
      final mortality = recs.fold<num>(0, (s, r) => s + _num(r['mortality']));
      final feed = recs.fold<num>(0, (s, r) => s + _num(r['feedKg']));
      final fid = d.selectedFlock == 'ALL' ? null : int.tryParse(d.selectedFlock);
      final birdsLeft = d.records.isEmpty
          ? 0
          : d.selectedFlock == 'ALL'
              ? sumLatestBirdsLeftByFlock(d.records)
              : fid == null
                  ? 0
                  : birdsLeftForFlock(d.records, fid);
      final rows = [...recs]..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
      final data = [
        for (final r in rows)
          (
            date: d.fmtDateTime(r),
            flock: '${r['flockName'] ?? (r['flockId'] != null ? 'Flock #${r['flockId']}' : '—')}',
            m9: _num(r['production9AM']),
            m12: _num(r['production12PM']),
            m4: _num(r['production4PM']),
            m4th: _num(r['production4thPick']),
            total: _num(r['totalProduction']),
          ),
      ];
      num sum(num Function(({String date, String flock, num m9, num m12, num m4, num m4th, num total})) f) => data.fold<num>(0, (s, x) => s + f(x));
      return (
        cards: [
          (label: 'Total Eggs', value: _loc(totalEggs), accent: null, note: null),
          (label: 'Total Crates', value: '${_loc(crates)} (+$loose loose)', accent: null, note: null),
          (label: 'Avg Daily Production', value: _loc(avg), accent: null, note: null),
          (label: 'Total Deaths', value: _loc(mortality), accent: 'rose', note: null),
          (label: 'Total Feed (kg)', value: _loc(feed), accent: null, note: null),
          (
            label: d.selectedFlock == 'ALL' ? 'Birds Left (sum per flock)' : 'Birds Left (selected flock)',
            value: _loc(birdsLeft),
            accent: 'indigo',
            note: null,
          ),
        ],
        tables: [
          DashTable(
            title: 'Daily Egg Production',
            description: 'Eggs collected per day and flock, with collection-time breakdown.',
            columns: const [
              ReportColumn('Date'),
              ReportColumn('Flock'),
              ReportColumn('1st Pick', right: true),
              ReportColumn('2nd Pick', right: true),
              ReportColumn('3rd Pick', right: true),
              ReportColumn('4th Pick', right: true),
              ReportColumn('Total', right: true),
              ReportColumn('Crates + Loose', right: true),
            ],
            rows: [
              for (final r in data)
                [r.date, r.flock, _loc(r.m9), _loc(r.m12), _loc(r.m4), _loc(r.m4th), _loc(r.total), '${r.total ~/ 30} + ${r.total.toInt() % 30}'],
            ],
            totals: data.isEmpty
                ? null
                : [
                    'Total',
                    '${data.length} ${data.length == 1 ? 'day' : 'days'}',
                    _loc(sum((x) => x.m9)),
                    _loc(sum((x) => x.m12)),
                    _loc(sum((x) => x.m4)),
                    _loc(sum((x) => x.m4th)),
                    _loc(totalEggs),
                    '$crates + $loose',
                  ],
          ),
        ],
      );

    case 'financial':
      // revenueByDate, in first-seen order then by date.
      final byDate = <String, ({num revenue, num expenses})>{};
      for (final s in sales) {
        final k = _key(s['saleDate'] ?? s['sale_date']);
        final c = byDate[k] ?? (revenue: 0, expenses: 0);
        byDate[k] = (revenue: c.revenue + _num(s['totalAmount']), expenses: c.expenses);
      }
      for (final e in exps) {
        final k = _key(e['expenseDate'] ?? e['expense_date']);
        final c = byDate[k] ?? (revenue: 0, expenses: 0);
        byDate[k] = (revenue: c.revenue, expenses: c.expenses + _num(e['amount']));
      }
      final keys = byDate.keys.toList()..sort();
      return (
        cards: [
          (label: 'Revenue (${sales.length} txn)', value: m(revenue), accent: 'green', note: null),
          (label: 'Expenses (${exps.length})', value: m(expensesAmount), accent: 'rose', note: null),
          (label: 'Net Profit / Loss', value: m(net), accent: net >= 0 ? 'green' : 'rose', note: null),
        ],
        tables: [
          DashTable(
            title: 'Revenue vs Expenses',
            description: 'Daily revenue, spending and net position.',
            columns: const [
              ReportColumn('Date'),
              ReportColumn('Revenue', right: true),
              ReportColumn('Expenses', right: true),
              ReportColumn('Net', right: true),
            ],
            rows: [
              for (final k in keys)
                [
                  k.isEmpty ? 'Invalid Date' : _localeDate(k),
                  m(byDate[k]!.revenue),
                  m(byDate[k]!.expenses),
                  m(byDate[k]!.revenue - byDate[k]!.expenses),
                ],
            ],
            cellColor: (row, col) {
              if (col != 3) return null;
              final k = keys.firstWhere((x) => (x.isEmpty ? 'Invalid Date' : _localeDate(x)) == row[0], orElse: () => '');
              final v = byDate[k];
              if (v == null) return null;
              return v.revenue - v.expenses >= 0 ? emerald700 : rose700;
            },
          ),
        ],
      );

    case 'daily':
      final bucket = <String, ({num eggs, num expenses})>{};
      for (final r in recs) {
        final k = _key(r['date']);
        final c = bucket[k] ?? (eggs: 0, expenses: 0);
        bucket[k] = (eggs: c.eggs + _num(r['totalProduction']), expenses: c.expenses);
      }
      for (final e in exps) {
        final k = _key(e['expenseDate'] ?? e['expense_date']);
        final c = bucket[k] ?? (eggs: 0, expenses: 0);
        bucket[k] = (eggs: c.eggs, expenses: c.expenses + _num(e['amount']));
      }
      final keys = bucket.keys.where((k) => k.isNotEmpty).toList()..sort();
      String? best, highest;
      for (final k in keys) {
        if (best == null || bucket[k]!.eggs > bucket[best]!.eggs) best = k;
        if (highest == null || bucket[k]!.expenses > bucket[highest]!.expenses) highest = k;
      }
      String perf(String k) {
        final v = bucket[k]!;
        final perUnit = v.expenses > 0 ? v.eggs / v.expenses : v.eggs;
        return v.expenses <= 0 ? '▲ No expense' : perUnit >= 1 ? '▲ Strong day' : '▼ Review costs';
      }

      return (
        cards: [
          (label: 'Daily Rows', value: _loc(keys.length), accent: null, note: null),
          (label: 'Best Egg Day', value: best == null ? 'No data' : '${_loc(bucket[best]!.eggs)} · ${_mmmd(best)}', accent: 'green', note: null),
          (
            label: 'Highest Expense Day',
            value: highest == null ? 'No data' : '${m(bucket[highest]!.expenses)} · ${_mmmd(highest)}',
            accent: 'rose',
            note: null,
          ),
          (label: 'Net Position', value: m(net), accent: net >= 0 ? 'green' : 'rose', note: null),
        ],
        tables: [
          DashTable(
            title: 'Daily Egg & Expense Report',
            description: 'Same-day production volume and spending.',
            columns: const [
              ReportColumn('Date'),
              ReportColumn('Total Eggs', right: true),
              ReportColumn('Crates + Loose'),
              ReportColumn('Daily Expenses', right: true),
              ReportColumn('Performance'),
            ],
            rows: [
              for (final k in keys)
                [
                  _mmmdy(k),
                  _loc(bucket[k]!.eggs),
                  '${bucket[k]!.eggs ~/ 30} crates + ${bucket[k]!.eggs.toInt() % 30} loose',
                  m(bucket[k]!.expenses),
                  perf(k),
                ],
            ],
            cellColor: (row, col) => col != 4 ? null : row[4].contains('Review') ? amber700 : emerald700,
          ),
        ],
      );

    default:
      final byProduct = <String, ({num qty, num revenue, int count})>{};
      for (final s in sales) {
        final k = '${s['product'] ?? ''}'.trim().isEmpty ? 'Unknown' : '${s['product']}'.trim();
        final c = byProduct[k] ?? (qty: 0, revenue: 0, count: 0);
        byProduct[k] = (qty: c.qty + _num(s['quantity']), revenue: c.revenue + _num(s['totalAmount']), count: c.count + 1);
      }
      final products = byProduct.entries.toList()..sort((a, b) => b.value.revenue.compareTo(a.value.revenue));
      final byCategory = <String, num>{};
      for (final e in exps) {
        final k = '${e['category'] ?? ''}'.trim().isEmpty ? 'Uncategorized' : '${e['category']}'.trim();
        byCategory[k] = (byCategory[k] ?? 0) + _num(e['amount']);
      }
      final categories = byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final byFlock = <int, ({String name, num eggs, num feed, num mortality, int days})>{};
      for (final r in recs) {
        final id = _num(r['flockId']).toInt();
        final c = byFlock[id] ?? (name: '${r['flockName'] ?? 'Flock #$id'}', eggs: 0, feed: 0, mortality: 0, days: 0);
        byFlock[id] = (
          name: c.name,
          eggs: c.eggs + _num(r['totalProduction']),
          feed: c.feed + _num(r['feedKg']),
          mortality: c.mortality + _num(r['mortality']),
          days: c.days + 1,
        );
      }
      final flocks = byFlock.entries.toList()..sort((a, b) => b.value.eggs.compareTo(a.value.eggs));
      return (
        cards: [
          (label: 'Sales Products', value: _loc(products.length), accent: null, note: null),
          (label: 'Expense Categories', value: _loc(categories.length), accent: null, note: null),
          (
            label: 'Top Product Revenue',
            value: products.isEmpty ? 'No data' : '${m(products.first.value.revenue)} · ${products.first.key}',
            accent: 'green',
            note: null,
          ),
          (
            label: 'Top Expense Category',
            value: categories.isEmpty ? 'No data' : '${m(categories.first.value)} · ${categories.first.key}',
            accent: 'rose',
            note: null,
          ),
        ],
        tables: [
          DashTable(
            title: 'Sales by Product Report',
            description: 'Quantities and revenue split by product.',
            columns: const [
              ReportColumn('Product'),
              ReportColumn('Transactions', right: true),
              ReportColumn('Quantity', right: true),
              ReportColumn('Revenue', right: true),
            ],
            rows: [
              for (final p in products) [p.key, _loc(p.value.count), _loc(p.value.qty), m(p.value.revenue)],
            ],
          ),
          DashTable(
            title: 'Expense Category Report',
            description: 'Where most spending is happening.',
            columns: const [ReportColumn('Category'), ReportColumn('Total', right: true)],
            rows: [
              for (final c in categories) [c.key, m(c.value)],
            ],
          ),
          DashTable(
            title: 'Flock Performance Report',
            description: 'Egg output, feed usage and deaths by flock.',
            columns: const [
              ReportColumn('Flock'),
              ReportColumn('Birds Left (latest)', right: true),
              ReportColumn('Total Eggs', right: true),
              ReportColumn('Avg Eggs / Day', right: true),
              ReportColumn('Feed (kg)', right: true),
              ReportColumn('Deaths', right: true),
            ],
            rows: [
              for (final f in flocks)
                [
                  f.value.name,
                  _loc(birdsLeftForFlock(d.records, f.key)),
                  _loc(f.value.eggs),
                  _loc(f.value.days > 0 ? (f.value.eggs / f.value.days).round() : 0),
                  _loc(f.value.feed),
                  _loc(f.value.mortality),
                ],
            ],
            cellColor: (row, col) => col == 1 ? const Color(0xFF3730A3) : null,
          ),
        ],
      );
  }
}

// ------------------------------------------------------------------ pieces

/// The search box plus a Filters sheet (Flock, Date From / To, Clear, Apply),
/// as the web's phone filter bar.
class DashboardFilterBar extends StatelessWidget {
  const DashboardFilterBar({super.key, required this.data, required this.onChanged});
  final DashboardData data;
  final VoidCallback onChanged;

  Future<void> _sheet(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheet) {
            void set(VoidCallback f) {
              f();
              setSheet(() {});
              onChanged();
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
              child: SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Filters', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 14),
                  const Text('Flock', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  AppSelect<String>(
                    value: data.selectedFlock,
                    hintText: 'All Flocks',
                    items: [
                      const AppSelectItem(value: 'ALL', label: 'All Flocks'),
                      for (final f in data.flocks)
                        if (f['flockId'] != null) AppSelectItem(value: '${_num(f['flockId']).toInt()}', label: '${f['name'] ?? ''}'),
                    ],
                    onChanged: (v) => set(() => data.selectedFlock = v ?? 'ALL'),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Date From', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        AppDateField(
                          value: businessDateAsDateTime(data.dateFrom),
                          hintText: 'Any',
                          firstDate: DateTime(2000),
                          onChanged: (d) => set(() => data.dateFrom = d == null ? '' : isoDay(d)),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Date To', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        AppDateField(
                          value: businessDateAsDateTime(data.dateTo),
                          hintText: 'Any',
                          firstDate: DateTime(2000),
                          onChanged: (d) => set(() => data.dateTo = d == null ? '' : isoDay(d)),
                        ),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: AppButton(label: 'Clear', variant: AppButtonVariant.outline, onPressed: () => set(data.clear))),
                    const SizedBox(width: 8),
                    Expanded(child: AppButton(label: 'Apply', onPressed: () => Navigator.of(ctx).pop())),
                  ]),
                ]),
              ),
            );
          },
        ),
      );

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(6)),
        child: Row(children: [
          Expanded(
            child: AppInput(
              initialValue: data.search,
              hintText: 'Search...',
              onChanged: (v) {
                data.search = v;
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          AppButton(
            label: 'Filters',
            icon: Icons.filter_list,
            variant: AppButtonVariant.outline,
            size: AppButtonSize.sm,
            onPressed: () => _sheet(context),
          ),
        ]),
      );
}

/// Cards, then one titled card per table.
class DashboardBody extends StatelessWidget {
  const DashboardBody({super.key, required this.content});
  final DashContent content;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SummaryCards(content.cards),
        for (final t in content.tables)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(t.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: slate900)),
              if (t.description != null)
                Padding(padding: const EdgeInsets.only(top: 2), child: Text(t.description!, style: const TextStyle(fontSize: 13, color: slate500))),
              const SizedBox(height: 12),
              ReportTable(
                columns: [for (final c in t.columns) (header: c.header, right: c.right, badge: false)],
                rows: t.rows,
                totals: t.totals,
                cellColor: t.cellColor,
              ),
            ]),
          ),
      ]);
}

/// CSV / Email / PDF for a whole view: every table at once.
class DashboardExportToolbar extends StatelessWidget {
  const DashboardExportToolbar({super.key, required this.session, required this.company, required this.view, required this.data, required this.content});
  final Session session;
  final Company company;
  final String view;
  final DashboardData data;
  final DashContent content;

  ReportDocument _doc() => ReportDocument(
        title: dashboardViewMeta[view]!.title,
        filename: dashboardFilename(view),
        farmName: company.name,
        fromDate: data.dateFrom.isEmpty ? null : data.dateFrom,
        toDate: data.dateTo.isEmpty ? null : data.dateTo,
        generatedBy: reportUser(session),
        currencyLabel: data.money.code,
        cards: [for (final c in content.cards) (label: c.label, value: c.value, accent: c.accent, note: c.note)],
        sections: [
          for (final t in content.tables) ReportSection(heading: t.title, columns: t.columns, rows: t.rows, totals: t.totals),
        ],
      );

  /// The dashboards' CSV: "Period: All to All" when no dates are set, then
  /// each table under its title.
  Future<void> _csv() async {
    String esc(Object? v) => '"${'${v ?? ''}'.replaceAll('"', '""')}"';
    final meta = '${esc(dashboardViewMeta[view]!.title)}\n${esc('Farm: ${company.name}')},'
        '${esc('Period: ${data.dateFrom.isEmpty ? 'All' : data.dateFrom} to ${data.dateTo.isEmpty ? 'All' : data.dateTo}')}\n';
    final blocks = [
      for (final t in content.tables)
        '${esc(t.title)}\n${t.columns.map((c) => esc(c.header)).join(',')}\n'
            '${[...t.rows, if (t.totals != null) t.totals!].map((r) => r.map(esc).join(',')).join('\n')}',
    ];
    final csv = '$meta\n${blocks.join('\n\n')}';
    await ReportExport.sharer('${dashboardFilename(view)}-${DateTime.now().toIso8601String().substring(0, 10)}.csv',
        [0xEF, 0xBB, 0xBF, ...const Utf8Codec().encode(csv)], 'text/csv', dashboardViewMeta[view]!.title);
  }

  @override
  Widget build(BuildContext context) {
    final hasData = content.tables.any((t) => t.rows.isNotEmpty);
    return _ExportButtonsWithBusy(
      disabled: !hasData,
      onCsv: _csv,
      onPdf: () => ReportExport.sharePdf(_doc()),
      onEmail: () => showReportEmailDialog(
        context,
        client: session.farmClient,
        document: _doc,
        // The dashboards prefill the signed-in user, as the web does.
        defaultRecipient: reportUser(session) ?? '',
      ),
    );
  }
}

class _ExportButtonsWithBusy extends StatefulWidget {
  const _ExportButtonsWithBusy({required this.disabled, required this.onCsv, required this.onPdf, required this.onEmail});
  final bool disabled;
  final Future<void> Function() onCsv, onPdf;
  final VoidCallback onEmail;

  @override
  State<_ExportButtonsWithBusy> createState() => _ExportButtonsWithBusyState();
}

class _ExportButtonsWithBusyState extends State<_ExportButtonsWithBusy> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() f, {bool busy = false}) async {
    if (busy) setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed. $e')));
    } finally {
      if (mounted && busy) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ReportExportButtons(
        onCsv: () => _run(widget.onCsv),
        onEmail: widget.onEmail,
        onPdf: () => _run(widget.onPdf, busy: true),
        busy: _busy,
        disabled: widget.disabled,
      );
}

// ----------------------------------------------------------------- screens

/// /poultry/reports/production · financial · daily · more — one dashboard on
/// its own page, with the reports' back button and titled header card.
class PoultryDashboardScreen extends StatefulWidget {
  const PoultryDashboardScreen({super.key, required this.session, required this.company, required this.view});
  final Session session;
  final Company company;
  final String view;

  @override
  State<PoultryDashboardScreen> createState() => _PoultryDashboardScreenState();
}

class _PoultryDashboardScreenState extends State<PoultryDashboardScreen> {
  DashboardData? _data;

  @override
  void initState() {
    super.initState();
    DashboardData.load(widget.session, widget.company).then((d) {
      if (mounted) setState(() => _data = d);
    });
  }

  @override
  Widget build(BuildContext context) {
    final meta = dashboardViewMeta[widget.view]!;
    final href = '/poultry/reports/${widget.view == 'insights' ? 'more' : widget.view}';
    final lead = sidebarLeading(context, widget.session, widget.company, href: href);
    final d = _data;
    final content = d == null ? null : buildDashboardContent(widget.view, d);
    return Scaffold(
      backgroundColor: slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: Text(meta.title)),
      body: d == null || content == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
              children: [
                Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.spaceBetween, children: [
                  AppButton(
                    label: 'Poultry reports',
                    icon: Icons.arrow_back,
                    variant: AppButtonVariant.outline,
                    size: AppButtonSize.sm,
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PoultryReportsCatalogScreen(session: widget.session, company: widget.company),
                    )),
                  ),
                  DashboardExportToolbar(session: widget.session, company: widget.company, view: widget.view, data: d, content: content),
                ]),
                const SizedBox(height: 12),
                ReportCard(children: [
                  Text(meta.title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: slate900)),
                  const SizedBox(height: 4),
                  Text(meta.description, style: const TextStyle(fontSize: 13, color: slate500)),
                ]),
                const SizedBox(height: 12),
                DashboardFilterBar(data: d, onChanged: () => setState(() {})),
                const SizedBox(height: 12),
                DashboardBody(content: content),
              ],
            ),
    );
  }
}

/// /reports — the four dashboards as tabs: Production, Financial, Daily, More.
class ReportsTabsScreen extends StatefulWidget {
  const ReportsTabsScreen({super.key, required this.session, required this.company, this.initialTab = 'production'});
  final Session session;
  final Company company;
  final String initialTab;

  @override
  State<ReportsTabsScreen> createState() => _ReportsTabsScreenState();
}

class _ReportsTabsScreenState extends State<ReportsTabsScreen> {
  DashboardData? _data;
  late String _tab = dashboardViewMeta.containsKey(widget.initialTab) ? widget.initialTab : 'production';

  @override
  void initState() {
    super.initState();
    DashboardData.load(widget.session, widget.company).then((d) {
      if (mounted) setState(() => _data = d);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/reports');
    final d = _data;
    final content = d == null ? null : buildDashboardContent(_tab, d);
    const tabs = [
      ('production', 'Production', Icons.egg_outlined),
      ('financial', 'Financial', Icons.account_balance_wallet_outlined),
      ('daily', 'Daily', Icons.calendar_month_outlined),
      ('insights', 'More', Icons.trending_up),
    ];
    return Scaffold(
      backgroundColor: slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
        children: [
          const Text('Comprehensive farm analytics and insights', style: TextStyle(fontSize: 13, color: slate600)),
          const SizedBox(height: 12),
          twoColumns(gap: 6, [
            for (final (key, label, icon) in tabs)
              Material(
                color: _tab == key ? Colors.white : slate100,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _tab = key),
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _tab == key ? slate300 : slate200),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(icon, size: 16, color: _tab == key ? slate900 : slate500),
                      const SizedBox(width: 6),
                      Text(label,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _tab == key ? slate900 : slate500)),
                    ]),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          if (d == null || content == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else ...[
            DashboardFilterBar(data: d, onChanged: () => setState(() {})),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: DashboardExportToolbar(session: widget.session, company: widget.company, view: _tab, data: d, content: content),
            ),
            const SizedBox(height: 12),
            DashboardBody(content: content),
          ],
        ],
      ),
    );
  }
}
