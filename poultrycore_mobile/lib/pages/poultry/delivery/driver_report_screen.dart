// Poultry → Operations → Delivery → Driver report (app/poultry-driver-report/
// page.tsx): period, dates and driver; Refresh; five figures; the per-driver
// totals and every delivery line in one paged list.

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../money/money_widgets.dart';
import '../reports/report_format.dart';
import '../sales/balances_logic.dart' show pageSlice;
import '../sales/balances_widgets.dart' show CompactPager, LoadingLine;
import '../trackers/tracker_logic.dart' show tNum, tStr, jsNum, loc;
import '../trackers/tracker_widgets.dart';

/// The detail sorted by driver ("Unassigned" for none), then product.
List<Map> sortDriverDetail(List<Map> detail) => [...detail]..sort((a, b) {
    final d = _driver(a).compareTo(_driver(b));
    return d != 0 ? d : tStr(a['productName']).compareTo(tStr(b['productName']));
  });

String _driver(Map r) => tStr(r['driverName']).isEmpty ? 'Unassigned' : tStr(r['driverName']);

typedef DriverHeadline = ({num runs, num cratesSold, num expected, num collected, num shortage});

DriverHeadline? driverHeadline(List<Map> totals) {
  if (totals.isEmpty) return null;
  num s(String k) => totals.fold<num>(0, (a, t) => a + tNum(t[k]));
  return (
    runs: s('deliveryRuns'),
    cratesSold: s('totalCratesSold'),
    expected: s('totalExpected'),
    collected: s('totalCollected'),
    shortage: s('totalShortage'),
  );
}

class DriverReportScreen extends StatefulWidget {
  const DriverReportScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<DriverReportScreen> createState() => _DriverReportScreenState();
}

class _DriverReportScreenState extends State<DriverReportScreen> {
  late String _from = defaultReportRange().from, _to = defaultReportRange().to;
  String _period = 'last30';
  int _driverId = 0;
  List<Map> _drivers = [], _totals = [], _detail = [];
  bool _hasReport = false, _busy = true;
  int _page = 1, _pageSize = 10;
  FarmMoney _fmt = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _fmt = m);
    });
    _load();
  }

  Future<void> _load([String? from, String? to]) async {
    setState(() => _busy = true);
    try {
      final r = await Future.wait([
        _api.get('/api/Poultry/drivers', query: {'farmId': _farmId}).then(rowsOf).catchError((_) => <Map>[]),
        _api.get('/api/Poultry/reports/driver-collection', query: {
          'farmId': _farmId,
          'fromDate': from ?? _from,
          'toDate': to ?? _to,
          if (_driverId != 0) 'poultryDriverId': '$_driverId',
        }),
      ]);
      if (!mounted) return;
      final rep = r[1];
      setState(() {
        _drivers = r[0] as List<Map>;
        _totals = rep is Map ? rowsOf(rep['totals']) : [];
        _detail = sortDriverDetail(rep is Map ? rowsOf(rep['detail']) : []);
        _hasReport = rep is Map;
        _page = 1;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      trackerToast(context, 'Could not load driver report', description: e.message, error: true);
      setState(() => _hasReport = false);
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _stat(String label, String value, {bool rose = false}) => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: rose ? TColors.rose600 : TColors.slate900)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-driver-report');
    final head = driverHeadline(_totals);
    final pageRows = pageSlice(_detail, _page, _pageSize);
    final shortStyle = const TextStyle(color: TColors.rose600, fontWeight: FontWeight.w600);

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Driver report')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          const Row(children: [
            Icon(Icons.bar_chart, size: 24, color: TColors.sky700),
            SizedBox(width: 8),
            Expanded(
              child: Text('Driver collection report', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900)),
            ),
          ]),
          const SizedBox(height: 14),
          TCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FilterLabel(
                'Period',
                AppSelect<String>(
                  value: _period,
                  hintText: 'Select period',
                  items: [
                    for (final (_, opts) in periodGroups)
                      for (final (k, l) in opts) AppSelectItem(value: k, label: l),
                  ],
                  onChanged: (k) {
                    if (k == null) return;
                    setState(() => _period = k);
                    final r = periodToRange(k);
                    if (r != null) {
                      setState(() {
                        _from = r.from;
                        _to = r.to;
                      });
                      _load(r.from, r.to);
                    }
                  },
                ),
              ),
              const SizedBox(height: 10),
              filterRow([
                FilterLabel('From', FilterDate(value: _from, hint: 'From', onChanged: (v) => setState(() {
                      _from = v;
                      _period = 'custom';
                    }))),
                FilterLabel('To', FilterDate(value: _to, hint: 'To', onChanged: (v) => setState(() {
                      _to = v;
                      _period = 'custom';
                    }))),
              ]),
              const SizedBox(height: 10),
              FilterLabel(
                'Driver',
                AppSelect<int>(
                  value: _driverId,
                  items: [
                    const AppSelectItem(value: 0, label: '— all drivers —'),
                    for (final d in _drivers)
                      if (d['isActive'] == true) AppSelectItem(value: tNum(d['poultryDriverId']).toInt(), label: tStr(d['driverName'])),
                  ],
                  onChanged: (v) => setState(() => _driverId = v ?? 0),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : () => _load(),
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          if (_busy)
            const TCard(child: LoadingLine('Loading report…'))
          else if (!_hasReport || _totals.isEmpty)
            const TCard(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No delivery activity in this period.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
              ),
            )
          else ...[
            if (head != null) ...[
              twoUp([
                _stat('Delivery runs', jsNum(head.runs)),
                _stat('Crates sold', loc(head.cratesSold)),
                _stat('Expected', _fmt(head.expected)),
                _stat('Collected', _fmt(head.collected)),
                _stat('Shortage', _fmt(head.shortage), rose: head.shortage > 0),
              ]),
              const SizedBox(height: 14),
            ],
            TCard(
              child: MobileCardList<Map>(
                items: _totals,
                keyOf: (t) => t['poultryDriverId'] != null ? tStr(t['poultryDriverId']) : 'none-${_driver(t)}',
                primary: _driver,
                secondary: (t) => '${jsNum(tNum(t['deliveryRuns']))} runs · Collected ${_fmt(tNum(t['totalCollected']))}',
                details: (t) => [
                  ('Runs', jsNum(tNum(t['deliveryRuns']))),
                  ('Crates loaded', jsNum(tNum(t['totalCratesLoaded']))),
                  ('Crates sold', jsNum(tNum(t['totalCratesSold']))),
                  ('Crates returned', jsNum(tNum(t['totalCratesReturned']))),
                  ('Crates lost', jsNum(tNum(t['totalCratesLost']))),
                  ('Expected', _fmt(tNum(t['totalExpected']))),
                  ('Collected', _fmt(tNum(t['totalCollected']))),
                  ('Shortage', _fmt(tNum(t['totalShortage']))),
                ],
                detailColor: (t, label) => label == 'Shortage' && tNum(t['totalShortage']) > 0 ? TColors.rose600 : null,
                table: (rows) => TrackerTable(
                  columns: const [
                    TCol('Driver', width: 130),
                    TCol('Runs', right: true, width: 70),
                    TCol('Loaded', right: true, width: 80),
                    TCol('Sold', right: true, width: 80),
                    TCol('Returned', right: true, width: 90),
                    TCol('Lost', right: true, width: 70),
                    TCol('Expected', right: true, width: 120),
                    TCol('Collected', right: true, width: 120),
                    TCol('Shortage', right: true, width: 120),
                  ],
                  rows: [
                    for (final t in rows)
                      [
                        cellText(_driver(t), bold: true),
                        cellText(jsNum(tNum(t['deliveryRuns']))),
                        cellText(jsNum(tNum(t['totalCratesLoaded']))),
                        cellText(jsNum(tNum(t['totalCratesSold']))),
                        cellText(jsNum(tNum(t['totalCratesReturned']))),
                        cellText(jsNum(tNum(t['totalCratesLost']))),
                        cellText(_fmt(tNum(t['totalExpected']))),
                        cellText(_fmt(tNum(t['totalCollected']))),
                        tNum(t['totalShortage']) > 0
                            ? Text(_fmt(tNum(t['totalShortage'])), style: shortStyle)
                            : cellText(_fmt(tNum(t['totalShortage']))),
                      ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            TCard(
              title: 'Deliveries',
              child: MobileCardList<Map>(
                items: pageRows,
                keyOf: (r) => '${tStr(r['poultryDriverReturnId'])}-${tStr(r['productName']).isEmpty ? 'none' : tStr(r['productName'])}',
                primary: (r) => '${_driver(r)} · ${tStr(r['productName']).isEmpty ? 'Product' : tStr(r['productName'])}',
                secondary: (r) =>
                    '${jsNum(tNum(r['cratesSold']))}/${jsNum(tNum(r['cratesLoaded']))} sold · ${_fmt(tNum(r['expectedAmount']))}',
                details: (r) => [
                  ('Driver', _driver(r)),
                  ('Date', _day(r)),
                  ('Product', tStr(r['productName']).isEmpty ? 'Product' : tStr(r['productName'])),
                  ('Loaded (crates)', jsNum(tNum(r['cratesLoaded']))),
                  ('Sold (crates)', jsNum(tNum(r['cratesSold']))),
                  ('Returned (crates)', jsNum(tNum(r['cratesReturned']))),
                  ('Damaged (crates)', jsNum(tNum(r['cratesDamaged']))),
                  ('Expected', _fmt(tNum(r['expectedAmount']))),
                ],
                pager: CompactPager(
                  total: _detail.length,
                  page: _page,
                  pageSize: _pageSize,
                  onPage: (p) => setState(() => _page = p),
                  onPageSize: (s) => setState(() {
                    _pageSize = s;
                    _page = 1;
                  }),
                ),
                table: (rows) => TrackerTable(
                  columns: const [
                    TCol('Driver', width: 130),
                    TCol('Date', width: 100),
                    TCol('Product', width: 120),
                    TCol('Loaded (crates)', right: true, width: 110),
                    TCol('Sold (crates)', right: true, width: 100),
                    TCol('Returned (crates)', right: true, width: 120),
                    TCol('Damaged (crates)', right: true, width: 120),
                    TCol('Expected', right: true, width: 120),
                  ],
                  rows: [
                    for (final r in rows)
                      [
                        cellText(_driver(r), bold: true),
                        cellText(_day(r)),
                        cellText(tStr(r['productName']).isEmpty ? 'Product' : tStr(r['productName'])),
                        cellText(jsNum(tNum(r['cratesLoaded']))),
                        cellText(jsNum(tNum(r['cratesSold']))),
                        cellText(jsNum(tNum(r['cratesReturned']))),
                        cellText(jsNum(tNum(r['cratesDamaged']))),
                        cellText(_fmt(tNum(r['expectedAmount']))),
                      ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _day(Map r) {
    final s = tStr(r['returnDate']);
    return s.length >= 10 ? s.substring(0, 10) : s;
  }
}
