import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../poultry/poultry_links.dart';
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart' show CompactPager;
import '../web_page_screen.dart';
import 'business_dates.dart';

/// The Missing Activity Detector, as `components/dashboard/farm-completeness-card.tsx`
/// with `flock-missing-dates.tsx`, `missing-by-date.tsx` and the helpers of
/// `lib/activity/completeness.ts`. The Farm API derives the report for any
/// business date (`/ActivityChecks`); nothing is computed here.
///
/// Its record links go to the production entry pages, which open as the web
/// page in-app until those forms are mirrored.
class FarmCompletenessCard extends StatefulWidget {
  const FarmCompletenessCard({
    super.key,
    required this.session,
    required this.company,
    this.businessDate,
    this.defaultExpanded = false,
    this.onReport,
    this.compact = false,
  });

  /// The web's `compact`: the summary only, with "Complete Missing
  /// Production" leading to the full page (Farm Alerts uses it).
  final bool compact;

  final Session session;
  final Company company;

  /// "yyyy-MM-dd"; null lets the server decide the company's today.
  final String? businessDate;
  final bool defaultExpanded;

  /// Told when a report arrives, so a host can learn the company's today.
  final ValueChanged<Map<String, dynamic>>? onReport;

  @override
  State<FarmCompletenessCard> createState() => _FarmCompletenessCardState();
}

const productionCheckKey = 'poultry.production.daily';

/// severityStyle: (label, badge bg, badge fg, accent).
(String, Color, Color, Color) severityStyle(Object? s) => switch (s) {
      'Critical' => ('Critical', const Color(0xFFFEE2E2), const Color(0xFFB91C1C), const Color(0xFFEF4444)),
      'Warning' => ('Warning', const Color(0xFFFEF3C7), const Color(0xFF92400E), const Color(0xFFF59E0B)),
      'Information' => ('Info', const Color(0xFFE0F2FE), const Color(0xFF0369A1), const Color(0xFF0EA5E9)),
      _ => ('Complete', const Color(0xFFD1FAE5), const Color(0xFF047857), const Color(0xFF10B981)),
    };

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

String _daysOutstanding(Object? d) {
  final n = _int(d) < 0 ? 0 : _int(d);
  return '$n day${n == 1 ? '' : 's'}';
}

/// missingDateHref.
String missingDateHref(Object flockId, String date, [Object? pendingId, Object? pendingStatus]) {
  if (pendingId != null) {
    return pendingStatus == 'Draft'
        ? '/batch-production-records/$pendingId/edit'
        : '/batch-production-records/$pendingId/allocate';
  }
  final d = toBusinessDate(date);
  return '/production-records/new?flockId=$flockId${d != null ? '&date=$d' : ''}';
}

/// flockStepThroughHref: step through each missed day in the normal form.
String flockStepThroughHref(Object flockId, String asOf) {
  final d = toBusinessDate(asOf);
  return '/production-records/new?flockId=$flockId&catchUp=1${d != null ? '&asOf=$d' : ''}';
}

/// batchEntryHref: Batch Production Entry prefilled with the flocks.
String? batchEntryHref(String businessDate, List<int> flockIds) {
  final d = toBusinessDate(businessDate);
  final ids = {for (final i in flockIds) if (i > 0) i}.take(500).toList();
  if (d == null || ids.isEmpty) return null;
  return '/batch-production-records/new?date=$d&flockIds=${ids.join('%2C')}&source=missing-production';
}

String itemActionHref(Map i, String businessDate) {
  if (i['state'] == 'Missing' && _int(i['daysOutstanding']) > 1) {
    return flockStepThroughHref(i['subjectId'], businessDate);
  }
  return missingDateHref(i['subjectId'], businessDate,
      i['state'] == 'AwaitingPosting' ? i['relatedRecordId'] : null, i['relatedRecordStatus']);
}

String itemActionLabel(Map i) {
  if (i['state'] == 'Missing' && _int(i['daysOutstanding']) > 1) return 'Record batch(${_int(i['daysOutstanding'])})';
  if (i['state'] != 'AwaitingPosting') return 'Record';
  return i['relatedRecordStatus'] == 'Draft' ? 'Finish batch' : 'Post batch';
}

/// flocksWithEarlierGaps: flocks complete on this day with earlier gaps.
List<Map<String, dynamic>> flocksWithEarlierGaps(List entries, Set<int> exclude) {
  final byFlock = <int, Map<String, dynamic>>{};
  for (final e in entries) {
    if (e is! Map) continue;
    final id = _int(e['flockId']);
    if (exclude.contains(id)) continue;
    final date = toBusinessDate(e['date']);
    if (date == null) continue;
    final f = byFlock[id];
    if (f == null) {
      byFlock[id] = {
        'flockId': id, 'flockName': '${e['flockName'] ?? ''}', 'batchName': e['batchName'],
        'houseName': e['houseName'], 'missingDays': 1, 'latestMissing': date,
      };
    } else {
      f['missingDays'] = (f['missingDays'] as int) + 1;
      if (date.compareTo(f['latestMissing'] as String) > 0) f['latestMissing'] = date;
    }
  }
  return byFlock.values.toList()
    ..sort((a, b) {
      final c = (b['missingDays'] as int).compareTo(a['missingDays'] as int);
      return c != 0 ? c : '${a['flockName']}'.compareTo('${b['flockName']}');
    });
}

class _FarmCompletenessCardState extends State<FarmCompletenessCard> {
  Map<String, dynamic>? _report;
  bool _hidden = false;
  bool _failed = false;
  bool _refreshing = false;
  String _view = 'flock';
  List? _earlier;

  /// Every flock's missing days are open by default; this holds the rows the
  /// user has CLOSED.
  final Set<String> _closedRows = {};
  int _page = 1, _pageSize = 10;

  ApiClient get _client => widget.session.farmClient;

  @override
  void initState() {
    super.initState();
    _load(false);
  }

  @override
  void didUpdateWidget(FarmCompletenessCard old) {
    super.didUpdateWidget(old);
    if (old.businessDate != widget.businessDate) {
      setState(() {
        _report = null;
        _earlier = null;
        _closedRows.clear();
        _page = 1;
      });
      _load(false);
    }
  }

  Future<void> _load(bool quiet) async {
    if (quiet) setState(() => _refreshing = true);
    try {
      final r = await _client.get('/api/ActivityChecks', query: {
        'farmId': widget.company.farmId,
        if (widget.businessDate != null) 'businessDate': widget.businessDate,
      });
      if (!mounted || r is! Map) return;
      final report = Map<String, dynamic>.from(r);
      setState(() {
        _report = report;
        _failed = false;
      });
      widget.onReport?.call(report);
      if (!widget.compact) _loadEarlier(report);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        // 403: this user may not see activity checks — the card goes away.
        if (e.statusCode == 403) {
          _hidden = true;
        } else if (!quiet) {
          _failed = true;
        }
      });
    } finally {
      if (mounted && quiet) setState(() => _refreshing = false);
    }
  }

  Map<String, dynamic>? _check(String key) {
    final checks = _report?['checks'];
    if (checks is! List) return null;
    for (final c in checks) {
      if (c is Map && c['key'] == key) return Map<String, dynamic>.from(c);
    }
    return null;
  }

  Map<String, dynamic>? get _production => _check(productionCheckKey);

  Future<void> _loadEarlier(Map report) async {
    final p = _production;
    final backlog = _int((p?['counters'] as Map?)?['backlogDates']);
    final date = toBusinessDate(report['businessDate']);
    if (backlog == 0 || date == null) {
      setState(() => _earlier = null);
      return;
    }
    try {
      final r = await _client.get('/api/ActivityChecks/production/missing-by-date',
          query: {'farmId': widget.company.farmId, 'days': '30', 'businessDate': date});
      if (mounted) setState(() => _earlier = r is Map && r['entries'] is List ? r['entries'] as List : const []);
    } catch (_) {
      if (mounted) setState(() => _earlier = const []);
    }
  }

  void _toggleRow(String k) => setState(() {
        if (!_closedRows.remove(k)) _closedRows.add(k);
      });

  /// A flock missing the shown day.
  Widget _dayRow(Map<String, dynamic> i, String businessDate) {
    final k = 'flock-${i['subjectId']}';
    return _FlockRow(
      title: '${i['label'] ?? ''}',
      awaiting: i['state'] == 'AwaitingPosting',
      batch: i['groupLabel'],
      house: i['locationLabel'],
      last: i['lastCompletedDate'] == null ? 'never' : formatShortDate(i['lastCompletedDate']),
      daysLabel: _daysOutstanding(i['daysOutstanding']),
      severity: i['severity'],
      actionLabel: itemActionLabel(i),
      open: !_closedRows.contains(k),
      onToggle: () => _toggleRow(k),
      onAction: () => _openWeb('Record production', itemActionHref(i, businessDate)),
      details: _FlockMissingDates(
        key: ValueKey('$businessDate-$k'),
        session: widget.session,
        company: widget.company,
        flockId: _int(i['subjectId']),
        businessDate: businessDate,
        onOpen: _openWeb,
      ),
    );
  }

  /// A flock complete on the shown day whose gaps are earlier days.
  Widget _earlierRow(Map<String, dynamic> f, String businessDate) {
    final k = 'earlier-${f['flockId']}';
    final n = f['missingDays'] as int;
    return _FlockRow(
      title: '${f['flockName']}',
      batch: f['batchName'],
      house: f['houseName'],
      last: formatShortDate(businessDate),
      daysLabel: '${_daysOutstanding(n)} earlier',
      severity: 'Critical',
      actionLabel: n > 1 ? 'Record batch($n)' : 'Record',
      open: !_closedRows.contains(k),
      onToggle: () => _toggleRow(k),
      onAction: () => _openWeb(
        'Record production',
        n > 1 ? flockStepThroughHref(f['flockId'], businessDate) : missingDateHref(f['flockId'], '${f['latestMissing']}'),
      ),
      details: _FlockMissingDates(
        key: ValueKey('$businessDate-$k'),
        session: widget.session,
        company: widget.company,
        flockId: f['flockId'] as int,
        businessDate: businessDate,
        onOpen: _openWeb,
      ),
    );
  }

  void _openWeb(String label, String href) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WebPageScreen(label: label, href: href, company: widget.company, session: widget.session),
      ));

  /// The full page's summary: the severity badge, then Today / Missing /
  /// Earlier days / Unsorted eggs as tiles, then the notes under them.
  Widget _fullSummary({
    required String sevLabel,
    required Color sevBg,
    required Color sevFg,
    required bool isToday,
    required String businessDate,
    required Map p,
    required int missing,
    required int backlogDates,
    required int backlogFlockDays,
    required int awaiting,
    required int duplicates,
    required Map? unsorted,
    required TextStyle Function([double]) muted,
  }) {
    final unsortedItems = [for (final i in (unsorted?['items'] as List? ?? const [])) if (i is Map) i];
    final oldest = unsortedItems.fold<int>(0, (m, i) => _int(i['daysOutstanding']) > m ? _int(i['daysOutstanding']) : m);
    final showUnsorted = unsorted != null && _int(unsorted['outstandingCount']) > 0;
    final tiles = <Widget>[
      _Tile(
        tone: missing > 0 ? _TileTone.amber : _TileTone.emerald,
        label: isToday ? 'Today' : formatShortDate(businessDate),
        value: '${_int(p['completedCount'])} / ${_int(p['expectedCount'])} recorded',
        sub: const Text('flocks recorded'),
      ),
      _Tile(
        tone: missing > 0 ? _TileTone.rose : _TileTone.emerald,
        label: isToday ? 'Missing today' : 'Missing this day',
        value: '$missing',
        sub: Text(missing > 0 ? 'production record${missing == 1 ? '' : 's'}' : 'nothing missing'),
      ),
      _Tile(
        tone: backlogFlockDays > 0 ? _TileTone.rose : _TileTone.emerald,
        label: 'Earlier days',
        value: '$backlogFlockDays',
        sub: Text(backlogFlockDays > 0 ? 'missing across $backlogDates day${backlogDates == 1 ? '' : 's'}' : 'all caught up'),
      ),
      if (showUnsorted)
        _Tile(
          tone: _TileTone.sky,
          label: 'Unsorted eggs',
          value: fmtNum(_int((unsorted['counters'] as Map?)?['eggs']), 0),
          sub: Wrap(children: [
            if (oldest >= 1) Text('oldest $oldest day${oldest == 1 ? '' : 's'} old · '),
            InkWell(
              onTap: () => openPoultryHref(context, widget.session, widget.company, '/poultry-egg-sorting', label: 'Egg Sorting'),
              child: const Text('Sort eggs', style: TextStyle(fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
            ),
          ]),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 4),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: sevBg, borderRadius: BorderRadius.circular(999)),
        child: Text(sevLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: sevFg)),
      ),
      const SizedBox(height: 8),
      // Two to a row (the card sits in an IntrinsicHeight, so no LayoutBuilder).
      for (var i = 0; i < tiles.length; i += 2) ...[
        if (i > 0) const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: tiles[i]),
          const SizedBox(width: 8),
          Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox.shrink()),
        ]),
      ],
      const SizedBox(height: 8),
      if (missing == 0 && backlogDates == 0)
        const Text('✓ All expected flock production has been recorded.', style: TextStyle(fontSize: 13, color: Color(0xFF047857)))
      else if (backlogDates == 0 && '${p['severityReason'] ?? ''}'.isNotEmpty)
        Text('${p['severityReason']}', style: muted(12)),
      if (awaiting > 0)
        Text('$awaiting of these ${awaiting == 1 ? 'is' : 'are'} in a batch production entry that has not been posted yet.',
            style: muted(12)),
      if (duplicates > 0)
        Text('$duplicates flock${duplicates == 1 ? ' has' : 's have'} more than one production record for this day.',
            style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (_hidden) return const SizedBox.shrink();
    if (_failed) {
      return AppCard(
        child: Row(children: [
          const Expanded(child: Text('Farm completeness is unavailable right now.')),
          AppButton(
            label: 'Retry',
            icon: Icons.refresh,
            variant: AppButtonVariant.outline,
            size: AppButtonSize.sm,
            onPressed: () {
              setState(() => _failed = false);
              _load(false);
            },
          ),
        ]),
      );
    }
    final report = _report;
    if (report == null) {
      return const AppCard(
        child: Row(children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Flexible(child: Text("Checking today's farm activity…")),
        ]),
      );
    }
    final p = _production;
    if (p == null) return const SizedBox.shrink();

    final businessDate = toBusinessDate(report['businessDate']) ?? '';
    final isToday = businessDate == toBusinessDate(report['companyToday']);
    final title = isToday ? "TODAY'S FARM COMPLETENESS" : 'FARM COMPLETENESS — ${formatShortDate(businessDate).toUpperCase()}';
    final (sevLabel, sevBg, sevFg, accent) = severityStyle(p['severity']);
    final counters = (p['counters'] as Map?) ?? const {};
    final missing = _int(p['outstandingCount']);
    final awaiting = _int(counters['awaitingPosting']);
    final duplicates = _int(counters['duplicateFlocks']);
    final backlogDates = _int(counters['backlogDates']);
    final backlogFlockDays = _int(counters['backlogFlockDays']);
    final hasWork = missing > 0 || backlogDates > 0;
    final items = [for (final i in (p['items'] as List? ?? const [])) if (i is Map) Map<String, dynamic>.from(i)];
    // 344: shown only when the farm sorts and earlier days' eggs are waiting.
    final unsorted = _check('poultry.eggs.unsorted');
    // The By flock list as one list, paged: flocks missing the day, then
    // flocks whose only gaps are earlier days.
    final earlierFlocks = _earlier == null
        ? const <Map<String, dynamic>>[]
        : flocksWithEarlierGaps(_earlier!, {for (final i in items) _int(i['subjectId'])});
    final flockRows = <(bool, Map<String, dynamic>)>[
      for (final i in items) (true, i),
      for (final f in earlierFlocks) (false, f),
    ];
    final pageRows = pageSlice(flockRows, _page, _pageSize);
    final notApplicable = p['status'] == 'NotApplicable';
    TextStyle muted([double size = 13]) => TextStyle(fontSize: size, color: tokens.mutedForeground);

    // The web's `border-l-4` severity edge. Flutter cannot round a border
    // whose sides differ in colour, so the edge is its own strip inside a
    // uniformly bordered, clipped card.
    return _AccentCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: hasWork ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(hasWork ? Icons.warning_amber_rounded : Icons.fact_check_outlined, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: widget.compact
                        ? muted(11.5).copyWith(fontWeight: FontWeight.w600, letterSpacing: .6)
                        : TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: .6, color: tokens.cardForeground)),
                const SizedBox(height: 4),
                if (notApplicable)
                  Text('No active flocks are expected to report production.', style: muted())
                else if (!widget.compact)
                  // Full page: one coloured tile per figure, so today, earlier
                  // days and unsorted eggs read as separate things to do.
                  _fullSummary(
                    sevLabel: sevLabel,
                    sevBg: sevBg,
                    sevFg: sevFg,
                    isToday: isToday,
                    businessDate: businessDate,
                    p: p,
                    missing: missing,
                    backlogDates: backlogDates,
                    backlogFlockDays: backlogFlockDays,
                    awaiting: awaiting,
                    duplicates: duplicates,
                    unsorted: unsorted,
                    muted: muted,
                  )
                else ...[
                  Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text.rich(TextSpan(style: muted(), children: [
                      TextSpan(text: '${isToday ? 'Today' : formatShortDate(businessDate)}: '),
                      TextSpan(
                        text: '${_int(p['completedCount'])} / ${_int(p['expectedCount'])} recorded',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: tokens.cardForeground),
                      ),
                    ])),
                    if (missing > 0)
                      Text.rich(TextSpan(style: muted(), children: [
                        const TextSpan(text: 'Missing: '),
                        TextSpan(text: '$missing', style: TextStyle(fontWeight: FontWeight.w600, color: tokens.cardForeground)),
                      ])),
                    if (backlogFlockDays > 0)
                      Text.rich(TextSpan(style: muted(), children: [
                        const TextSpan(text: 'Earlier: '),
                        TextSpan(
                          text: '$backlogFlockDays missing',
                          style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFBE123C)),
                        ),
                      ])),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: sevBg, borderRadius: BorderRadius.circular(999)),
                      child: Text(sevLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: sevFg)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  if (missing == 0 && backlogDates == 0)
                    const Text('✓ All expected flock production has been recorded.',
                        style: TextStyle(fontSize: 13, color: Color(0xFF047857)))
                  else if (backlogDates > 0)
                    Text(
                      '${missing == 0 ? '${isToday ? 'Today' : 'This day'} is complete, but ' : 'Also missing: '}'
                      '$backlogFlockDays production record${backlogFlockDays == 1 ? '' : 's'}'
                      '${missing == 0 ? '${backlogFlockDays == 1 ? ' is' : ' are'} still missing' : ''} across '
                      '$backlogDates earlier day${backlogDates == 1 ? '' : 's'}.',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFFBE123C)),
                    )
                  else if ('${p['severityReason'] ?? ''}'.isNotEmpty)
                    Text('${p['severityReason']}', style: muted(12)),
                  if (awaiting > 0)
                    Text(
                      '$awaiting of these ${awaiting == 1 ? 'is' : 'are'} in a batch production entry that has not been posted yet.',
                      style: muted(12),
                    ),
                  if (duplicates > 0)
                    Text(
                      '$duplicates flock${duplicates == 1 ? ' has' : 's have'} more than one production record for this day.',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)),
                    ),
                  if (unsorted != null && _int(unsorted['outstandingCount']) > 0)
                    // Egg sorting (344): earlier days' eggs still unsorted.
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
                        Text(
                          '${unsorted['severityReason'] ?? '${fmtNum(_int((unsorted['counters'] as Map?)?['eggs']), 0)} eggs from earlier days are still unsorted.'}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)),
                        ),
                        InkWell(
                          onTap: () => openPoultryHref(context, widget.session, widget.company, '/poultry-egg-sorting', label: 'Egg Sorting'),
                          child: const Text('Sort eggs',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFFB45309), decoration: TextDecoration.underline)),
                        ),
                      ]),
                    ),
                ],
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          // The web hid "Show missing" and "Complete … Production" on the full
          // page: the list is always open and each flock's Record does the job.
          // The compact card (Farm Alerts) keeps its button, which only leads
          // to the full page.
          if (!widget.compact)
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Refresh farm completeness',
                onPressed: _refreshing ? null : () => _load(true),
                icon: _refreshing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 20),
              ),
            )
          else if (hasWork)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD97706), foregroundColor: Colors.white),
                onPressed: () => openPoultryHref(context, widget.session, widget.company, '/poultry-farm-completeness',
                    label: 'Farm Completeness'),
                child: const Text('Complete Missing Production'),
              ),
            ),
          if (!widget.compact && hasWork) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'flock', label: Text('By flock')),
                  ButtonSegment(value: 'date', label: Text('By date')),
                ],
                selected: {_view},
                onSelectionChanged: (s) => setState(() => _view = s.first),
              ),
            ),
            const SizedBox(height: 8),
            if (_view == 'date')
              _MissingByDate(session: widget.session, company: widget.company, businessDate: businessDate, onOpen: _openWeb)
            else ...[
              for (var idx = 0; idx < pageRows.length; idx++)
                if (pageRows[idx].$1)
                  _dayRow(pageRows[idx].$2, businessDate)
                else
                  Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    // "Earlier days missing" heads the earlier-only flocks, and
                    // is repeated at the top of a page that starts with them.
                    if (missing > 0 && (idx == 0 || pageRows[idx - 1].$1))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                        child: Text('EARLIER DAYS MISSING', style: muted(11.5).copyWith(fontWeight: FontWeight.w600, letterSpacing: .6)),
                      ),
                    _earlierRow(pageRows[idx].$2, businessDate),
                  ]),
              // Flocks complete on this day with earlier missing days, still loading.
              if (backlogDates > 0 && _earlier == null)
                Padding(padding: const EdgeInsets.all(8), child: Text('Loading flocks with earlier missing days…', style: muted(12))),
              if (flockRows.isNotEmpty)
                CompactPager(
                  total: flockRows.length,
                  page: _page,
                  pageSize: _pageSize,
                  onPage: (p) => setState(() => _page = p),
                  onPageSize: (n) => setState(() {
                    _pageSize = n;
                    _page = 1;
                  }),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

/// A card with a coloured left edge, as `border-l-4` draws it on the web.
class _AccentCard extends StatelessWidget {
  const _AccentCard({required this.accent, required this.child});
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, color: accent),
          Expanded(child: Padding(padding: const EdgeInsets.all(14), child: child)),
        ]),
      ),
    );
  }
}

/// One flock in the missing list; tap to open its missing days.
class _FlockRow extends StatelessWidget {
  const _FlockRow({
    required this.title,
    required this.batch,
    required this.house,
    required this.last,
    required this.daysLabel,
    required this.severity,
    required this.actionLabel,
    required this.open,
    required this.onToggle,
    required this.onAction,
    required this.details,
    this.awaiting = false,
  });
  final String title;
  final Object? batch;
  final Object? house;
  final String last;
  final String daysLabel;
  final Object? severity;
  final String actionLabel;
  final bool open;
  final bool awaiting;
  final VoidCallback onToggle;
  final VoidCallback onAction;
  final Widget details;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final (_, bg, fg, _) = severityStyle(severity);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: open ? tokens.muted : null,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: tokens.mutedForeground),
                  const SizedBox(width: 4),
                  Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
                  if (awaiting)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: const Color(0xFFF0F9FF), borderRadius: BorderRadius.circular(4)),
                      child: const Text('awaiting posting', style: TextStyle(fontSize: 11, color: Color(0xFF0369A1))),
                    ),
                ]),
                const SizedBox(height: 4),
                // Phone: batch, house and last production under the name.
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: Text(
                    '${[batch, house].where((v) => v != null && '$v'.isNotEmpty).join(' · ').ifEmpty('—')} · last $last',
                    style: TextStyle(fontSize: 12, color: tokens.mutedForeground),
                  ),
                ),
                const SizedBox(height: 6),
                // Wraps rather than overflowing on a narrow phone.
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
                      child: Text(daysLabel, style: TextStyle(fontSize: 12, color: fg)),
                    ),
                    AppButton(label: actionLabel, variant: AppButtonVariant.outline, size: AppButtonSize.sm, onPressed: onAction),
                  ],
                ),
              ]),
            ),
          ),
          if (open) details,
        ],
      ),
    );
  }
}

/// FlockMissingDateRows: one flock's missing days, 30 then 90 back.
class _FlockMissingDates extends StatefulWidget {
  const _FlockMissingDates({
    super.key,
    required this.session,
    required this.company,
    required this.flockId,
    required this.businessDate,
    required this.onOpen,
  });
  final Session session;
  final Company company;
  final int flockId;
  final String businessDate;
  final void Function(String label, String href) onOpen;

  @override
  State<_FlockMissingDates> createState() => _FlockMissingDatesState();
}

class _FlockMissingDatesState extends State<_FlockMissingDates> {
  int _days = 30;
  Map? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await widget.session.farmClient.get('/api/ActivityChecks/production/missing-dates', query: {
        'farmId': widget.company.farmId,
        'flockId': '${widget.flockId}',
        'days': '$_days',
        if (widget.businessDate.isNotEmpty) 'businessDate': widget.businessDate,
      });
      if (mounted) setState(() => _data = r is Map ? r : const {});
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : 'Could not load the missing days.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final small = TextStyle(fontSize: 12, color: tokens.mutedForeground);
    if (_error != null) {
      return Padding(padding: const EdgeInsets.fromLTRB(28, 0, 10, 10), child: Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFFBE123C))));
    }
    final data = _data;
    if (data == null) {
      return Padding(padding: const EdgeInsets.fromLTRB(28, 0, 10, 10), child: Text('Loading missing days…', style: small));
    }
    final dates = [for (final d in (data['dates'] as List? ?? const [])) if (d is Map) d];
    final window = _int(data['windowDays']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 10, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final d in dates)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('↳ ${formatWeekdayDate(d['date'])}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  Text(
                    d['pendingBatchRecordId'] != null
                        ? 'In batch entry #${d['pendingBatchRecordId']} — not posted yet'
                        : 'No production record',
                    style: TextStyle(
                      fontSize: 12,
                      color: d['pendingBatchRecordId'] != null ? const Color(0xFF075985) : const Color(0xFF92400E),
                    ),
                  ),
                  Text(daysAgoLabel(d['date'], data['businessDate']), style: small),
                ]),
              ),
              AppButton(
                label: d['pendingBatchRecordId'] != null
                    ? (d['pendingBatchStatus'] == 'Draft' ? 'Finish batch' : 'Post batch')
                    : 'Record',
                variant: AppButtonVariant.outline,
                size: AppButtonSize.sm,
                onPressed: () => widget.onOpen('Record production',
                    missingDateHref(widget.flockId, '${d['date']}', d['pendingBatchRecordId'], d['pendingBatchStatus'])),
              ),
            ]),
          ),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
          Text(
            dates.isEmpty
                ? 'No missing days in the last $window days.'
                : '${dates.length} missing day${dates.length == 1 ? '' : 's'} in the last $window days.',
            style: small,
          ),
          if (window < 90)
            TextButton(
              onPressed: () {
                setState(() {
                  _days = 90;
                  _data = null;
                });
                _load();
              },
              child: const Text('Look back 90 days', style: TextStyle(fontSize: 12)),
            ),
        ]),
      ]),
    );
  }
}

/// MissingByDateTable: the same gaps grouped by day.
class _MissingByDate extends StatefulWidget {
  const _MissingByDate({required this.session, required this.company, required this.businessDate, required this.onOpen});
  final Session session;
  final Company company;
  final String businessDate;
  final void Function(String label, String href) onOpen;

  @override
  State<_MissingByDate> createState() => _MissingByDateState();
}

class _MissingByDateState extends State<_MissingByDate> {
  int _days = 30;
  Map? _data;
  String? _error;
  final Set<String> _open = {};
  int _page = 1, _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await widget.session.farmClient.get('/api/ActivityChecks/production/missing-by-date', query: {
        'farmId': widget.company.farmId,
        'days': '$_days',
        if (widget.businessDate.isNotEmpty) 'businessDate': widget.businessDate,
      });
      if (mounted) setState(() => _data = r is Map ? r : const {});
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : 'Could not load missing days.');
    }
  }

  /// groupMissingByDate: per day, flocks with nothing started and the
  /// unposted batches already covering some.
  List<Map<String, dynamic>> _groups(List entries) {
    final out = <Map<String, dynamic>>[];
    final byDate = <String, Map<String, dynamic>>{};
    for (final e in entries) {
      if (e is! Map) continue;
      final date = toBusinessDate(e['date']);
      if (date == null) continue;
      final g = byDate.putIfAbsent(date, () {
        final n = {'date': date, 'missing': <Map>[], 'batches': <int, Map<String, dynamic>>{}};
        out.add(n);
        return n;
      });
      if (e['pendingBatchRecordId'] == null) {
        (g['missing'] as List<Map>).add(e);
      } else {
        final batches = g['batches'] as Map<int, Map<String, dynamic>>;
        final b = batches.putIfAbsent(_int(e['pendingBatchRecordId']),
            () => {'id': _int(e['pendingBatchRecordId']), 'status': e['pendingBatchStatus'], 'flocks': <Map>[]});
        (b['flocks'] as List<Map>).add(e);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final small = TextStyle(fontSize: 12, color: tokens.mutedForeground);
    if (_error != null) return Text(_error!, style: const TextStyle(fontSize: 13, color: Color(0xFFBE123C)));
    final data = _data;
    if (data == null) return Text('Loading…', style: small);
    final groups = _groups(data['entries'] as List? ?? const []);
    final window = _int(data['windowDays']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (groups.isEmpty) Text('No missing production in the last $window days.', style: TextStyle(color: tokens.mutedForeground)),
      for (final g in pageSlice(groups, _page, _pageSize)) ...[
        Builder(builder: (context) {
          final date = g['date'] as String;
          final missing = g['missing'] as List<Map>;
          final batches = (g['batches'] as Map<int, Map<String, dynamic>>).values.toList();
          final isOpen = _open.contains(date);
          final href = batchEntryHref(date, [for (final m in missing) _int(m['flockId'])]);
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(border: Border.all(color: tokens.border), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              InkWell(
                onTap: () => setState(() {
                  if (!_open.remove(date)) _open.add(date);
                }),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(isOpen ? Icons.expand_less : Icons.expand_more, size: 18, color: tokens.mutedForeground),
                      const SizedBox(width: 4),
                      Text(formatWeekdayDate(date), style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      Text(daysAgoLabel(date, data['businessDate']), style: small),
                    ]),
                    const SizedBox(height: 4),
                    Text('Flocks: ${missing.isEmpty ? '—' : missing.length}', style: small),
                    // Phone: the unposted batches sit under the date.
                    if (batches.isNotEmpty)
                      Wrap(spacing: 8, children: [
                        for (final b in batches)
                          InkWell(
                            onTap: () => widget.onOpen(
                              'Batch production',
                              missingDateHref((b['flocks'] as List<Map>).first['flockId'], date, b['id'], b['status']),
                            ),
                            child: Text('batch #${b['id']} (${(b['flocks'] as List).length})',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF0369A1), decoration: TextDecoration.underline)),
                          ),
                      ]),
                    if (href != null) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: AppButton(
                          label: 'Record batch (${missing.length})',
                          variant: AppButtonVariant.outline,
                          size: AppButtonSize.sm,
                          onPressed: () => widget.onOpen('Batch Production Entry', href),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
              if (isOpen)
                for (final m in missing)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 10, 8),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('↳ ${m['flockName'] ?? ''}', style: const TextStyle(fontSize: 13)),
                          Text([m['batchName'], m['houseName']].where((x) => x != null && '$x'.isNotEmpty).join(' · ').ifEmpty('—'),
                              style: small),
                        ]),
                      ),
                      AppButton(
                        label: 'Record',
                        variant: AppButtonVariant.outline,
                        size: AppButtonSize.sm,
                        onPressed: () => widget.onOpen('Record production', missingDateHref(m['flockId'], date)),
                      ),
                    ]),
                  ),
            ]),
          );
        }),
      ],
      if (groups.isNotEmpty)
        CompactPager(
          total: groups.length,
          page: _page,
          pageSize: _pageSize,
          onPage: (p) => setState(() => _page = p),
          onPageSize: (n) => setState(() {
            _pageSize = n;
            _page = 1;
          }),
        ),
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
        Text('Last $window days.', style: small),
        if (window < 90)
          TextButton(
            onPressed: () {
              setState(() {
                _days = 90;
                _data = null;
              });
              _load();
            },
            child: const Text('Look back 90 days', style: TextStyle(fontSize: 12)),
          ),
      ]),
    ]);
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

enum _TileTone { emerald, amber, rose, sky }

/// One figure on the full-page summary: label, big number, a line under it.
class _Tile extends StatelessWidget {
  const _Tile({required this.tone, required this.label, required this.value, required this.sub});
  final _TileTone tone;
  final String label;
  final String value;
  final Widget sub;

  @override
  Widget build(BuildContext context) {
    final (border, bg, fg) = switch (tone) {
      _TileTone.emerald => (const Color(0xFFA7F3D0), const Color(0xFFECFDF5), const Color(0xFF047857)),
      _TileTone.amber => (const Color(0xFFFDE68A), const Color(0xFFFFFBEB), const Color(0xFFB45309)),
      _TileTone.rose => (const Color(0xFFFECDD3), const Color(0xFFFFF1F2), const Color(0xFFBE123C)),
      _TileTone.sky => (const Color(0xFFBAE6FD), const Color(0xFFF0F9FF), const Color(0xFF0369A1)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: fg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4, color: fg.withValues(alpha: .8))),
          Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          DefaultTextStyle.merge(style: const TextStyle(fontSize: 12), child: sub),
        ]),
      ),
    );
  }
}
