import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';
import '../shared/farm_completeness_card.dart';
import 'days_of_supply_screen.dart';
import 'flock_alerts_logic.dart';
import 'flock_alerts_screen.dart';
import 'poultry_links.dart';
import 'trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import 'trackers/tracker_widgets.dart';

/// Poultry → Tools → Farm Alerts, as `app/poultry-alerts/page.tsx`: everything
/// that needs the farmer's attention on one page — a status line, four tiles
/// (Production, Egg sorting, Flock health, Stock) that jump to their section,
/// then the Farm Completeness, Flock Alerts and Restock Forecast cards.
///
/// The numbers are `hooks/use-farm-alert-count.ts`'s breakdown (the header
/// bell's), each source failing on its own to "not available".
class FarmAlertBreakdown {
  int? productionToday, productionEarlier, productionExpected, productionRecorded;
  int? unsortedDays, unsortedEggs, flockAlerts, stockActionable;
  int total = 0;
  DateTime loadedAt = DateTime.now();
}

Future<FarmAlertBreakdown> loadFarmAlertBreakdown(Session session, Company company) async {
  final c = session.farmClient;
  final q = {'farmId': company.farmId};
  Future<Object?> settle(Future<Object?> f) async {
    try {
      return await f;
    } on ApiException {
      return null;
    }
  }

  final r = await Future.wait([
    settle(c.get('/api/ActivityChecks', query: q)),
    settle(c.get('/api/Poultry/flock-alerts', query: {...q, 'status': 'active'})),
    settle(c.get('/api/Poultry/stock-supply', query: q)),
  ]);
  final b = FarmAlertBreakdown();
  int i(Object? v) => tNum(v).toInt();
  Map? check(String key) {
    final checks = r[0] is Map ? (r[0] as Map)['checks'] : null;
    for (final x in checks is List ? checks : const []) {
      if (x is Map && x['key'] == key) return x;
    }
    return null;
  }

  final production = check(productionCheckKey);
  if (production != null && production['status'] != 'NotApplicable') {
    final counters = production['counters'] is Map ? production['counters'] as Map : const {};
    b.productionToday = i(production['outstandingCount']);
    b.productionEarlier = i(counters['backlogFlockDays']);
    b.productionExpected = production['expectedCount'] == null ? null : i(production['expectedCount']);
    b.productionRecorded = production['completedCount'] == null ? null : i(production['completedCount']);
  }
  final unsorted = check('poultry.eggs.unsorted');
  if (unsorted != null && unsorted['status'] != 'NotApplicable') {
    b.unsortedDays = i(unsorted['outstandingCount']);
    b.unsortedEggs = i(unsorted['counters'] is Map ? (unsorted['counters'] as Map)['eggs'] : null);
  }
  if (r[1] is List) b.flockAlerts = (r[1] as List).length;
  if (r[2] is List) b.stockActionable = (r[2] as List).where((x) => x is Map && supplyActionable.contains(x['status'])).length;
  b.total = (b.productionToday ?? 0) + (b.productionEarlier ?? 0) + (b.unsortedDays ?? 0) + (b.flockAlerts ?? 0) + (b.stockActionable ?? 0);
  return b;
}

typedef FarmAlertTile = ({String id, String title, IconData icon, String value, String detail, String tone});

String _fmt(int n) => fmtNum(n, 0);

List<FarmAlertTile> tilesFor(FarmAlertBreakdown? d) {
  final productionOpen = (d?.productionToday ?? 0) + (d?.productionEarlier ?? 0);
  final FarmAlertTile production = d?.productionToday == null
      ? (id: 'production', title: 'Production', icon: Icons.fact_check_outlined, value: '—', detail: 'Not available', tone: 'off')
      : (
          id: 'production',
          title: 'Production',
          icon: Icons.fact_check_outlined,
          value: productionOpen == 0 ? 'Up to date' : '${_fmt(productionOpen)} missing',
          detail: [
            (d!.productionExpected ?? 0) > 0
                ? 'Today ${_fmt(d.productionRecorded ?? 0)} / ${_fmt(d.productionExpected!)} recorded'
                : 'No flocks due today',
            if ((d.productionEarlier ?? 0) > 0) '${_fmt(d.productionEarlier!)} earlier',
          ].join(' · '),
          tone: productionOpen == 0 ? 'ok' : 'warn',
        );
  final FarmAlertTile sorting = d?.unsortedDays == null
      ? (id: 'production', title: 'Egg sorting', icon: Icons.egg_outlined, value: 'Off', detail: 'Sorting is not switched on', tone: 'off')
      : (
          id: 'production',
          title: 'Egg sorting',
          icon: Icons.egg_outlined,
          value: d!.unsortedDays == 0 ? 'Up to date' : '${_fmt(d.unsortedEggs ?? 0)} eggs',
          detail: d.unsortedDays == 0
              ? 'Earlier days are all sorted'
              : 'from ${_fmt(d.unsortedDays!)} earlier day${d.unsortedDays == 1 ? '' : 's'}, unsorted',
          tone: d.unsortedDays == 0 ? 'ok' : 'warn',
        );
  final FarmAlertTile flocks = d?.flockAlerts == null
      ? (id: 'flocks', title: 'Flock health', icon: Icons.monitor_heart_outlined, value: '—', detail: 'Not available', tone: 'off')
      : (
          id: 'flocks',
          title: 'Flock health',
          icon: Icons.monitor_heart_outlined,
          value: d!.flockAlerts == 0 ? 'All normal' : '${_fmt(d.flockAlerts!)} alert${d.flockAlerts == 1 ? '' : 's'}',
          detail: d.flockAlerts == 0 ? 'No flock out of line with its figures' : 'Flocks out of line with their recent figures',
          tone: d.flockAlerts == 0 ? 'ok' : 'warn',
        );
  final FarmAlertTile stock = d?.stockActionable == null
      ? (id: 'stock', title: 'Stock', icon: Icons.inventory_2_outlined, value: '—', detail: 'Not available', tone: 'off')
      : (
          id: 'stock',
          title: 'Stock',
          icon: Icons.inventory_2_outlined,
          value: d!.stockActionable == 0 ? 'Well stocked' : '${_fmt(d.stockActionable!)} running low',
          detail: d.stockActionable == 0 ? 'Nothing runs out soon' : 'Items to reorder or top up',
          tone: d.stockActionable == 0 ? 'ok' : 'warn',
        );
  return [production, sorting, flocks, stock];
}

/// TONE: (card bg, card border, icon bg, icon fg, value).
(Color, Color, Color, Color, Color) _tone(String t) => switch (t) {
      'ok' => (const Color(0x99ECFDF5), TColors.emerald200, TColors.emerald500, Colors.white, TColors.emerald800),
      'warn' => (TColors.amber50, TColors.amber300, const Color(0xFFF59E0B), Colors.white, TColors.amber900),
      _ => (Colors.white, TColors.slate200, TColors.slate200, TColors.slate600, TColors.slate600),
    };

class FarmAlertsScreen extends StatefulWidget {
  const FarmAlertsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<FarmAlertsScreen> createState() => _FarmAlertsScreenState();
}

class _FarmAlertsScreenState extends State<FarmAlertsScreen> {
  FarmAlertBreakdown? _data;
  bool _refreshing = false;

  /// Bumped by Refresh: remounts the cards so they re-read too.
  int _cardsKey = 0;
  Duration _offset = DateTime.now().timeZoneOffset;
  final _sections = {'production': GlobalKey(), 'flocks': GlobalKey(), 'stock': GlobalKey()};

  @override
  void initState() {
    super.initState();
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
  }

  Future<void> _load() async {
    final b = await loadFarmAlertBreakdown(widget.session, widget.company);
    if (mounted) setState(() => _data = b);
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _cardsKey += 1;
    });
    await _load();
    if (mounted) setState(() => _refreshing = false);
  }

  void _jump(String id) {
    final ctx = _sections[id]?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0);
  }

  void _open(String href, String label) => openPoultryHref(context, widget.session, widget.company, href, label: label);

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-alerts');
    final data = _data;
    final total = data?.total ?? 0;
    final tiles = tilesFor(data);
    final (statusBorder, headBg, iconBg) = data == null
        ? (TColors.slate200, TColors.slate50, TColors.slate200)
        : total == 0
            ? (TColors.emerald200, TColors.emerald50, TColors.emerald500)
            : (TColors.amber200, TColors.amber50, const Color(0xFFF59E0B));
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Farm Alerts')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // ------------------------------------------------ status
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: statusBorder),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [headBg, Colors.white])),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Stack(clipBehavior: Clip.none, children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
                          child: data == null
                              ? const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2))
                              : Icon(total == 0 ? Icons.check_circle_outline : Icons.notifications_outlined, color: Colors.white),
                        ),
                        if (data != null && total > 0)
                          Positioned(
                            right: -6,
                            top: -6,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 20),
                              height: 20,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: TColors.red600, borderRadius: BorderRadius.circular(999)),
                              child: Text(total > 99 ? '99+' : '$total',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                            ),
                          ),
                      ]),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Farm Alerts', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900)),
                          Text(
                            data == null
                                ? 'Checking the farm…'
                                : total == 0
                                    ? 'All clear — nothing needs your attention right now.'
                                    : '${_fmt(total)} thing${total == 1 ? '' : 's'} need${total == 1 ? 's' : ''} your attention.',
                            style: const TextStyle(fontSize: 13, color: TColors.slate600),
                          ),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (data != null)
                        Text('Updated ${fmtInstant(data.loadedAt.toUtc().toIso8601String(), _offset)}',
                            style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                      OutlinedButton.icon(
                        onPressed: _refreshing ? null : _refresh,
                        icon: _refreshing
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.refresh, size: 16),
                        label: const Text('Refresh'),
                      ),
                    ]),
                  ]),
                ),
                // ------------------------------------------------ tiles
                Container(
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: TColors.slate100))),
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _tile(tiles[i], data != null),
                    ],
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            // ------------------------------------------------ sections
            _section(
              'production',
              'Production & egg sorting',
              'Production still to record for today or earlier days, and eggs from earlier days still to sort.',
              '/poultry-farm-completeness',
              'Farm Completeness',
              FarmCompletenessCard(key: ValueKey('fc-$_cardsKey'), session: widget.session, company: widget.company, compact: true),
            ),
            const SizedBox(height: 24),
            _section(
              'flocks',
              'Flock health',
              'Flocks whose mortality, eggs or feed are out of line with their own recent figures.',
              '/poultry-flock-alerts',
              'All flock alerts',
              FlockAlertsCard(key: ValueKey('fa-$_cardsKey'), session: widget.session, company: widget.company),
            ),
            const SizedBox(height: 24),
            _section(
              'stock',
              'Stock',
              'Feed, medication and supplies that will run out soonest at their actual usage.',
              '/poultry-restock-forecast',
              'Inventory Restock Forecast',
              StockSupplyCard(key: ValueKey('ss-$_cardsKey'), session: widget.session, company: widget.company),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _tile(FarmAlertTile t, bool loaded) {
    final (bg, border, iconBg, iconFg, valueColor) = _tone(t.tone);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _jump(t.id),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: border), borderRadius: BorderRadius.circular(12)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
              child: Icon(t.icon, size: 20, color: iconFg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.title.toUpperCase(),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: .6, color: TColors.slate500)),
                Text(loaded ? t.value : '…', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: valueColor)),
                Text(loaded ? t.detail : ' ',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: TColors.slate600)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _section(String id, String title, String description, String href, String linkLabel, Widget child) => Column(
        key: _sections[id],
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title.toUpperCase(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: .8, color: TColors.slate500)),
          Text(description, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => _open(href, linkLabel),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(linkLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.amber700))),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward, size: 14, color: TColors.amber700),
            ]),
          ),
          const SizedBox(height: 8),
          child,
        ],
      );
}

/// A card with a coloured left edge (`border-l-4`).
Widget _edgeCard(Color edge, Widget child) => Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, color: edge),
          Expanded(child: Padding(padding: const EdgeInsets.all(16), child: child)),
        ]),
      ),
    );

Widget _loadingCard(String text) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: TColors.slate500))),
      ]),
    );

Widget _cardHead(IconData icon, Color tile, String label, Widget summary, VoidCallback onViewAll) => Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.start,
      spacing: 8,
      runSpacing: 8,
      children: [
        Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: tile, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label.toUpperCase(),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: .6, color: TColors.slate500)),
              const SizedBox(height: 4),
              summary,
            ]),
          ),
        ]),
        OutlinedButton(style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: onViewAll, child: const Text('View all')),
      ],
    );

Widget _moreLine(int more, VoidCallback onViewAll) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(children: [
        Text('and $more more — ', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        InkWell(
          onTap: onViewAll,
          child: const Text('view all', style: TextStyle(fontSize: 12, color: TColors.sky700, decoration: TextDecoration.underline)),
        ),
      ]),
    );

/// components/dashboard/flock-alerts-card.tsx: the active flock alerts, four
/// shown. Quietly absent on failure.
class FlockAlertsCard extends StatefulWidget {
  const FlockAlertsCard({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<FlockAlertsCard> createState() => _FlockAlertsCardState();
}

class _FlockAlertsCardState extends State<FlockAlertsCard> {
  List<Map>? _alerts;
  bool _failed = false;
  static const _show = 4;

  @override
  void initState() {
    super.initState();
    widget.session.farmClient.get('/api/Poultry/flock-alerts', query: {'farmId': widget.company.farmId, 'status': 'active'}).then((r) {
      if (mounted) setState(() => _alerts = sortAlerts(rowsOf(r)));
    }, onError: (Object _) {
      if (mounted) setState(() => _failed = true);
    });
  }

  void _all() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FlockAlertsScreen(session: widget.session, company: widget.company)));

  void _one(Map a) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FlockAlertsScreen(session: widget.session, company: widget.company, openAlertId: tIntOrNull(a['alertId']))));

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    final alerts = _alerts;
    if (alerts == null) return _loadingCard('Checking flocks for unusual figures…');
    final s = summarizeAlerts(alerts);
    final worstSeverity = alerts
        .where((a) => isActiveAlertStatus(a['status']))
        .fold<Object?>(null, (w, a) => severityRank(a['severity']) > severityRank(w) ? a['severity'] : w);
    final edge = s.active > 0 ? alertSeverityStyle(worstSeverity).edge : TColors.emerald500;
    final tile = s.critical > 0 ? TColors.rose500 : (s.active > 0 ? const Color(0xFFF59E0B) : TColors.emerald500);
    return _edgeCard(
      edge,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _cardHead(
          Icons.monitor_heart_outlined,
          tile,
          'Flock Alerts',
          s.active == 0
              ? const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.check_circle_outline, size: 16, color: TColors.emerald700),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text('No flock is out of line with its recent figures.', style: TextStyle(fontSize: 13, color: TColors.emerald700)),
                  ),
                ])
              : Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${s.active}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: ' flock alert${s.active == 1 ? '' : 's'}'),
                    if (s.critical > 0) TextSpan(text: ' · ${s.critical} critical', style: const TextStyle(color: TColors.rose700)),
                    if (s.acknowledged > 0) TextSpan(text: ' · ${s.acknowledged} acknowledged', style: const TextStyle(color: TColors.slate500)),
                  ]),
                  style: const TextStyle(fontSize: 13, color: TColors.slate700),
                ),
          _all,
        ),
        if (s.active > 0) ...[
          const SizedBox(height: 12),
          for (var i = 0; i < alerts.length && i < _show; i++) _alertLine(alerts[i], first: i == 0),
          if (alerts.length > _show) _moreLine(alerts.length - _show, _all),
        ],
      ]),
    );
  }

  Widget _alertLine(Map a, {required bool first}) {
    final signals = alertSignals(a);
    final active = signals.where((x) => x['isActive'] == true);
    final lead = active.isNotEmpty ? active.first : (signals.isNotEmpty ? signals.first : null);
    final explanation = lead?['explanation'] is List && (lead!['explanation'] as List).isNotEmpty ? tStr((lead['explanation'] as List).first) : '';
    final days = tNum(a['consecutiveDays']).toInt();
    return InkWell(
      onTap: () => _one(a),
      child: Container(
        decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: TColors.slate100))),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(
            TextSpan(children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(padding: const EdgeInsets.only(right: 8), child: severityBadge(a['severity'])),
              ),
              TextSpan(text: alertFlockLabel(a), style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
              TextSpan(text: ' — ${alertHeadline(a)}', style: const TextStyle(color: TColors.slate600)),
            ]),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            '${formatLongDate(alertDay(a['businessDate']))}'
            '${a['status'] != 'Open' ? ' · ${alertStatusStyle(a['status']).label}' : ''}'
            '${days > 1 ? ' · $days days in a row' : ''}'
            '${explanation.isNotEmpty ? ' · $explanation' : ''}',
            style: const TextStyle(fontSize: 12, color: TColors.slate500),
          ),
        ]),
      ),
    );
  }
}

/// components/dashboard/stock-supply-card.tsx: the items that will run out
/// soonest, five shown, with Restock. Hidden with no raw materials, quietly
/// absent on failure.
class StockSupplyCard extends StatefulWidget {
  const StockSupplyCard({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<StockSupplyCard> createState() => _StockSupplyCardState();
}

class _StockSupplyCardState extends State<StockSupplyCard> {
  List<Map>? _rows;
  bool _failed = false;
  static const _show = 5;

  @override
  void initState() {
    super.initState();
    widget.session.farmClient.get('/api/Poultry/stock-supply', query: {'farmId': widget.company.farmId}).then((r) {
      final rows = rowsOf(r);
      sortBySeverity(rows);
      if (mounted) setState(() => _rows = rows);
    }, onError: (Object _) {
      if (mounted) setState(() => _failed = true);
    });
  }

  void _all() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DaysOfSupplyScreen(session: widget.session, company: widget.company)));

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    final rows = _rows;
    if (rows == null) return _loadingCard('Checking stock levels…');
    if (rows.isEmpty) return const SizedBox.shrink();
    final urgent = rows.where((r) => supplyActionable.contains(r['status'])).toList();
    final healthy = rows.where((r) => r['status'] == 'Healthy').length;
    final warning = rows.first['warningDays'] == null ? 7 : tNum(rows.first['warningDays']);
    final bad = urgent.any((r) => const {'Negative', 'OutOfStock', 'Critical'}.contains(r['status']));
    final edge = bad ? TColors.rose500 : (urgent.isNotEmpty ? const Color(0xFFF59E0B) : TColors.emerald500);
    return _edgeCard(
      edge,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _cardHead(
          Icons.inventory_2_outlined,
          urgent.isNotEmpty ? const Color(0xFFF59E0B) : TColors.emerald500,
          'Inventory Restock Forecast',
          urgent.isEmpty
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.check_circle_outline, size: 16, color: TColors.emerald700),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('Nothing in use is expected to run out within ${fmtNum(warning, 1)} days.',
                        style: const TextStyle(fontSize: 13, color: TColors.emerald700)),
                  ),
                ])
              : Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${urgent.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: ' item${urgent.length == 1 ? ' needs' : 's need'} attention'),
                    if (healthy > 0) TextSpan(text: ' · $healthy healthy', style: const TextStyle(color: TColors.slate500)),
                  ]),
                  style: const TextStyle(fontSize: 13, color: TColors.slate700),
                ),
          _all,
        ),
        if (urgent.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (var i = 0; i < urgent.length && i < _show; i++) _line(urgent[i], first: i == 0),
          if (urgent.length > _show) _moreLine(urgent.length - _show, _all),
        ],
      ]),
    );
  }

  Widget _line(Map r, {required bool first}) {
    final (label, bg, fg) = supplyStatusStyle(tStr(r['status']));
    final out = supplyStockoutText(r);
    return Container(
      decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: TColors.slate100))),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text.rich(
            TextSpan(children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
                    child: Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: fg)),
                  ),
                ),
              ),
              TextSpan(text: tStr(r['itemName']), style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
              TextSpan(text: ' — ${supplyDaysText(r)}', style: const TextStyle(color: TColors.slate600)),
            ]),
            style: const TextStyle(fontSize: 13),
          ),
          Text(
            '${supplyQty(r['currentQuantity'], r['unitOfMeasure'])} in stock'
            '${r['avgDailyUsage'] != null ? ' · using about ${supplyQty(r['avgDailyUsage'], r['unitOfMeasure'])} a day' : ''}'
            '${out != null ? ' · $out' : ''}',
            style: const TextStyle(fontSize: 12, color: TColors.slate500),
          ),
        ]),
        OutlinedButton(
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: () => openRestock(context, widget.session, widget.company, r),
          child: const Text('Restock'),
        ),
      ]),
    );
  }
}
