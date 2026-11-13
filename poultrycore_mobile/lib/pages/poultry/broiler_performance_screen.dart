import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../shared/business_dates.dart' show fmtNum;
import 'flock_closeout_screen.dart' show FlockLifetimeScreen;
import 'flock_closeout_widgets.dart' show FlockCloseoutApi;
import 'trackers/tracker_widgets.dart' show rowsOf;
import 'reports/report_format.dart' show FarmMoney;

import 'package:poultrycore_mobile/design/tone.dart';

/// Analytics → Trackers → Broiler performance (`/poultry-broiler-performance`,
/// migration 402), as the web's `app/poultry-broiler-performance/page.tsx`.
///
/// Every broiler flock side by side on the figures a meat flock is judged by:
/// liveability, average weight, FCR, EPEF, kg produced and cost / revenue /
/// profit per kg. Each row comes from the server (fnflock_broilerkpis); the
/// farm totals add the quantities underneath ([broilerTotals]), never averages
/// of ratios. On a phone the web shows one card per flock, so does this.
class BroilerPerformanceScreen extends StatefulWidget {
  const BroilerPerformanceScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<BroilerPerformanceScreen> createState() => _BroilerPerformanceScreenState();
}

/// The web's round: Math.round((n + EPSILON) × 10^dp) / 10^dp.
double _r(num n, int dp) {
  var f = 1.0;
  for (var i = 0; i < dp; i++) {
    f *= 10;
  }
  return ((n + 2.220446049250313e-16) * f + 0.5).floorToDouble() / f;
}

num? _numOrNull(Object? v) => v == null ? null : (v is num ? v : num.tryParse('$v'));
num _num(Object? v) => _numOrNull(v) ?? 0;

/// broiler-kpis.ts `BroilerTotals`.
class BroilerTotals {
  const BroilerTotals({
    required this.flocks,
    required this.flocksWithKg,
    required this.birdsStarted,
    required this.deaths,
    required this.liveabilityPct,
    required this.kgProduced,
    required this.feedKgOfKnown,
    required this.fcr,
    required this.totalCostOfKnown,
    required this.costPerKg,
    required this.profit,
    required this.kgIsEstimated,
  });
  final int flocks;

  /// Flocks whose kg produced is known. Only these count towards FCR and cost per kg.
  final int flocksWithKg;
  final num birdsStarted;
  final num deaths;
  final double? liveabilityPct;
  final double kgProduced;
  final double feedKgOfKnown;
  final double? fcr;
  final double totalCostOfKnown;
  final double? costPerKg;
  final double profit;
  final bool kgIsEstimated;
}

/// Broiler figures across several flocks: three flocks' FCR is their total
/// feed over their total kg, so a small flock cannot pull the farm's figure
/// as hard as a big one.
BroilerTotals broilerTotals(List<Map> rows) {
  final known = rows.where((x) => _numOrNull(x['kgProduced']) != null && _num(x['kgProduced']) > 0).toList();
  final birdsStarted = rows.fold<num>(0, (s, x) => s + _num(x['birdsStarted']));
  final deaths = rows.fold<num>(0, (s, x) => s + _num(x['deaths']));
  final kg = known.fold<num>(0, (s, x) => s + _num(x['kgProduced']));
  final feed = known.fold<num>(0, (s, x) => s + _num(x['feedKg']));
  final cost = known.fold<num>(0, (s, x) => s + _num(x['totalCost']));
  return BroilerTotals(
    flocks: rows.length,
    flocksWithKg: known.length,
    birdsStarted: birdsStarted,
    deaths: deaths,
    liveabilityPct: birdsStarted > 0 ? _r(100 * (birdsStarted - deaths) / birdsStarted, 2) : null,
    kgProduced: _r(kg, 3),
    feedKgOfKnown: _r(feed, 3),
    fcr: kg > 0 && feed > 0 ? _r(feed / kg, 3) : null,
    totalCostOfKnown: _r(cost, 2),
    costPerKg: kg > 0 ? _r(cost / kg, 2) : null,
    profit: _r(rows.fold<num>(0, (s, x) => s + _num(x['profit'])), 2),
    kgIsEstimated: known.any((x) => x['kgIsEstimated'] == true),
  );
}

/// "1.826": FCR is read to three places on farms.
String fmtFcr(Object? v) => _numOrNull(v) == null ? '—' : _num(v).toStringAsFixed(3);

/// "2.42 kg"
String fmtKgEach(Object? v) => _numOrNull(v) == null ? '—' : '${_num(v).toStringAsFixed(2)} kg';

/// "2,300 kg"
String fmtKgTotal(Object? v) => _numOrNull(v) == null ? '—' : '${fmtNum(_num(v).round(), 0)} kg';

enum _Show { all, open, closed }

class _BroilerPerformanceScreenState extends State<BroilerPerformanceScreen> {
  List<Map> _rows = const [];
  bool _loading = true;
  String _error = '';
  _Show _show = _Show.all;
  FarmMoney _money = const FarmMoney();

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final res = await FlockCloseoutApi(widget.session, widget.company).broilerKpis(broilersOnly: true);
      if (!mounted) return;
      setState(() => _rows = rowsOf(res));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : 'Could not load the broiler figures.');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _m(Object? v) => _numOrNull(v) == null ? '—' : _money(_num(v));
  static String _pct(Object? v) => _numOrNull(v) == null ? '—' : '${_num(v).toStringAsFixed(2)}%';
  static bool _closed(Map r) => '${r['closedDate'] ?? ''}'.isNotEmpty;

  List<Map> get _shown => [
        for (final r in _rows)
          if (_show == _Show.all || (_show == _Show.closed ? _closed(r) : !_closed(r))) r,
      ];

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-broiler-performance');
    final shown = _shown;
    final t = broilerTotals(shown);
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Broiler performance')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(key: const ValueKey('broiler-performance-list'), padding: const EdgeInsets.fromLTRB(14, 16, 14, 28), children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: _orange100, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.set_meal_outlined, size: 20, color: _orange700),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Broiler performance', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _slate900)),
                Text('Liveability, weight, feed conversion and cost per kg for every broiler flock.',
                    style: TextStyle(fontSize: 13.5, color: _slate600)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: _showToggle()),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Tone.bg(0xFFFEF2F2),
                border: Border.all(color: const Tone.line(0xFFFECACA)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(_error, style: const TextStyle(fontSize: 13.5, color: Tone.fg(0xFFB91C1C))),
            ),
          ],
          const SizedBox(height: 12),
          _tiles([
            ('FCR', fmtFcr(t.fcr),
                t.flocksWithKg < t.flocks ? '${t.flocksWithKg} of ${t.flocks} flocks have a known kg' : 'kg feed per kg live weight'),
            ('Liveability', _pct(t.liveabilityPct), '${fmtNum(t.deaths, 0)} died of ${fmtNum(t.birdsStarted, 0)}'),
            ('Kg produced', fmtKgTotal(t.kgProduced), t.kgIsEstimated ? 'Partly estimated' : 'From sales and weigh-ins'),
            ('Cost per kg', _m(t.costPerKg), 'Chick cost included'),
          ]),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Tone.bg(0xFFFFFFFF),
              border: Border.all(color: _slate200),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _loading
                ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                : shown.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No broiler flocks${_show == _Show.all ? '' : _show == _Show.open ? ' running' : ' closed'} yet. '
                          'A flock is a broiler flock when it is set to Broilers on the Flocks page.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13.5, color: _slate500),
                        ),
                      )
                    : Column(children: [
                        for (final (i, r) in shown.indexed) ...[
                          if (i > 0) const Divider(height: 1, color: _slate200),
                          _card(r),
                        ],
                      ]),
          ),
          const SizedBox(height: 12),
          const Text(
            'FCR is feed kg over live kg produced. Kg produced is the weight on bird sales, plus an estimate for birds sold '
            'without a weight (at the average sale weight) and for birds still in the house (at the latest weigh-in). '
            'EPEF = liveability % × average weight kg ÷ (age days × FCR) × 100. Cost per kg includes the chick cost.',
            style: TextStyle(fontSize: 12, color: _slate500),
          ),
        ]),
      ),
    );
  }

  /// The web's phone card: name, status · age, six figures, what is missing.
  /// Tapping opens the flock's lifetime page (`/flock-closeout/{id}`).
  Widget _card(Map r) {
    final id = int.tryParse('${r['flockId'] ?? ''}') ?? 0;
    final epef = _numOrNull(r['epef']);
    final missing = '${r['missing'] ?? ''}';
    return InkWell(
      key: ValueKey('broiler-$id'),
      onTap: id <= 0
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FlockLifetimeScreen(session: widget.session, company: widget.company, flockId: id),
              )),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text('${r['flockName'] ?? ''}', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: _slate900)),
            ),
            const SizedBox(width: 8),
            Text('${_closed(r) ? 'Closed' : 'Running'} · ${_num(r['ageInDays']).round()} d',
                style: const TextStyle(fontSize: 12, color: _slate500)),
          ]),
          const SizedBox(height: 8),
          _mini([
            ('FCR', fmtFcr(r['fcr'])),
            ('Liveability', _pct(r['liveabilityPct'])),
            ('Avg weight', fmtKgEach(r['avgLiveWeightKg'])),
          ]),
          const SizedBox(height: 8),
          _mini([
            ('EPEF', epef == null ? '—' : fmtNum(epef.round(), 0)),
            ('Cost / kg', _m(r['costPerKg'])),
            ('Profit / kg', _m(r['profitPerKg'])),
          ]),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(missing, style: const TextStyle(fontSize: 12, color: Tone.fg(0xFFB45309))),
          ],
        ]),
      ),
    );
  }

  Widget _mini(List<(String, String)> figs) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (label, value) in figs)
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, color: _slate500)),
              Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _slate900)),
            ]),
          ),
      ]);

  /// All · Running · Closed.
  Widget _showToggle() => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: const Tone.bg(0xFFFFFFFF),
          border: Border.all(color: _slate200),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (v, label) in const [(_Show.all, 'All'), (_Show.open, 'Running'), (_Show.closed, 'Closed')])
            Semantics(
              inMutuallyExclusiveGroup: true,
              checked: _show == v,
              button: true,
              child: InkWell(
                key: ValueKey('broiler-show-$label'),
                borderRadius: BorderRadius.circular(4),
                onTap: () => setState(() => _show = v),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: _show == v ? Tone.button(const Tone.bg(0xFFF97316)) : null,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(label,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: _show == v ? Colors.white : _slate600)),
                ),
              ),
            ),
        ]),
      );

  /// Two per row, as the web's grid-cols-2 on a phone.
  Widget _tiles(List<(String, String, String)> tiles) => Column(children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _tile(tiles[i])),
              const SizedBox(width: 10),
              Expanded(child: _tile(tiles[i + 1])),
            ]),
          ),
        ],
      ]);

  Widget _tile((String, String, String) t) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Tone.bg(0xFFFFFFFF),
          border: Border.all(color: _slate200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.$1.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: .5, color: _slate500)),
          const SizedBox(height: 4),
          Text(t.$2, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: _slate900)),
          const SizedBox(height: 2),
          Text(t.$3, style: const TextStyle(fontSize: 12, color: _slate500)),
        ]),
      );
}

const _orange100 = Tone.bg(0xFFFFEDD5);
const _orange700 = Tone.fg(0xFFC2410C);
const _slate200 = Tone.line(0xFFE2E8F0);
const _slate500 = Tone.fg(0xFF64748B);
const _slate600 = Tone.fg(0xFF475569);
const _slate900 = Tone.fg(0xFF0F172A);
