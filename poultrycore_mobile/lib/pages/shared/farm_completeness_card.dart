import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../models/company.dart';
import '../../state/session.dart';
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
  });

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
  if (i['state'] == 'Missing' && _int(i['daysOutstanding']) > 1) return 'Record ${_int(i['daysOutstanding'])} days';
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
  late bool _expanded = widget.defaultExpanded;
  String _view = 'flock';
  List? _earlier;
  final Set<String> _openRows = {};

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
        _openRows.clear();
        _expanded = widget.defaultExpanded;
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
      _loadEarlier(report);
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

  Map<String, dynamic>? get _production {
    final checks = _report?['checks'];
    if (checks is! List) return null;
    for (final c in checks) {
      if (c is Map && c['key'] == productionCheckKey) return Map<String, dynamic>.from(c);
    }
    return null;
  }

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

  void _openWeb(String label, String href) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WebPageScreen(label: label, href: href, company: widget.company, session: widget.session),
      ));

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
          Text("Checking today's farm activity…"),
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
    final completeHref = batchEntryHref(businessDate, [
      for (final i in items) if (i['subjectType'] == 'flock' && i['state'] == 'Missing') _int(i['subjectId']),
    ]);
    final earlierFlocks = _earlier == null
        ? const <Map<String, dynamic>>[]
        : flocksWithEarlierGaps(_earlier!, {for (final i in items) _int(i['subjectId'])});
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
                Text(title, style: muted(11.5).copyWith(fontWeight: FontWeight.w600, letterSpacing: .6)),
                const SizedBox(height: 4),
                if (notApplicable)
                  Text('No active flocks are expected to report production.', style: muted())
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
                ],
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            IconButton(
              tooltip: 'Refresh farm completeness',
              onPressed: _refreshing ? null : () => _load(true),
              icon: _refreshing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 20),
            ),
            if (hasWork)
              AppButton(
                label: _expanded ? 'Hide missing' : 'Show missing',
                icon: _expanded ? Icons.expand_less : Icons.expand_more,
                variant: AppButtonVariant.outline,
                size: AppButtonSize.sm,
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
            if (completeHref != null)
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD97706)),
                onPressed: () => _openWeb('Batch Production Entry', completeHref),
                child: Text(backlogDates > 0
                    ? 'Complete ${isToday ? "Today's" : "This Day's"} Production'
                    : 'Complete Missing Production'),
              ),
          ]),
          if (_expanded && hasWork) ...[
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
              for (final i in items) ...[
                _FlockRow(
                  title: '${i['label'] ?? ''}',
                  awaiting: i['state'] == 'AwaitingPosting',
                  batch: i['groupLabel'],
                  house: i['locationLabel'],
                  last: i['lastCompletedDate'] == null ? 'Never' : formatShortDate(i['lastCompletedDate']),
                  daysLabel: _daysOutstanding(i['daysOutstanding']),
                  severity: i['severity'],
                  actionLabel: itemActionLabel(i),
                  open: _openRows.contains('flock-${i['subjectId']}'),
                  onToggle: () => setState(() {
                    final k = 'flock-${i['subjectId']}';
                    if (!_openRows.remove(k)) _openRows.add(k);
                  }),
                  onAction: () => _openWeb('Record production', itemActionHref(i, businessDate)),
                  details: _FlockMissingDates(
                    session: widget.session,
                    company: widget.company,
                    flockId: _int(i['subjectId']),
                    businessDate: businessDate,
                    onOpen: _openWeb,
                  ),
                ),
              ],
              if (backlogDates > 0 && _earlier == null)
                Padding(padding: const EdgeInsets.all(8), child: Text('Loading flocks with earlier missing days…', style: muted(12))),
              if (earlierFlocks.isNotEmpty && missing > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                  child: Text('EARLIER DAYS MISSING', style: muted(11.5).copyWith(fontWeight: FontWeight.w600, letterSpacing: .6)),
                ),
              for (final f in earlierFlocks)
                _FlockRow(
                  title: '${f['flockName']}',
                  batch: f['batchName'],
                  house: f['houseName'],
                  last: formatShortDate(businessDate),
                  daysLabel: '${_daysOutstanding(f['missingDays'])} earlier',
                  severity: 'Critical',
                  actionLabel: (f['missingDays'] as int) > 1 ? 'Record ${f['missingDays']} days' : 'Record',
                  open: _openRows.contains('earlier-${f['flockId']}'),
                  onToggle: () => setState(() {
                    final k = 'earlier-${f['flockId']}';
                    if (!_openRows.remove(k)) _openRows.add(k);
                  }),
                  onAction: () => _openWeb(
                    'Record production',
                    (f['missingDays'] as int) > 1
                        ? flockStepThroughHref(f['flockId'], businessDate)
                        : missingDateHref(f['flockId'], '${f['latestMissing']}'),
                  ),
                  details: _FlockMissingDates(
                    session: widget.session,
                    company: widget.company,
                    flockId: f['flockId'] as int,
                    businessDate: businessDate,
                    onOpen: _openWeb,
                  ),
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
    String d(Object? v) => v == null || '$v'.isEmpty ? '—' : '$v';
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
                Text('Batch: ${d(batch)} · House/Pen: ${d(house)}',
                    style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
                Text('Last production: $last', style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
                const SizedBox(height: 6),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
                    child: Text(daysLabel, style: TextStyle(fontSize: 12, color: fg)),
                  ),
                  const Spacer(),
                  AppButton(label: actionLabel, variant: AppButtonVariant.outline, size: AppButtonSize.sm, onPressed: onAction),
                ]),
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
      for (final g in groups) ...[
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
                    Text('Flocks missing: ${missing.isEmpty ? '—' : missing.length}', style: small),
                    if (batches.isNotEmpty)
                      Wrap(spacing: 8, children: [
                        Text('In an unposted batch:', style: small),
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
