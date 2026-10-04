import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/inputs.dart';
import '../../design/web_mobile.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../lookup_loader.dart';
import '../shared/business_dates.dart';
import '../shared/reason_dialog.dart';
import '../web_page_screen.dart';

/// Poultry → Tools → Distribute Feed, as `app/poultry-feed-distribution/page.tsx`
/// with the rules of `lib/production/feed-distribution.ts`: one feed to many
/// flocks for one business date, in one post. Each flock gets the feed on its
/// production record, exactly as if entered one by one.
///
/// Suggested Feed is only a suggestion; Actual is what posts, typed by the
/// farmer. Flocks without exactly one production record that day are locked.
class FeedDistributionScreen extends StatefulWidget {
  const FeedDistributionScreen({super.key, required this.session, required this.company, this.initialDate});
  final Session session;
  final Company company;

  /// A past day to open on, as `?date=`.
  final String? initialDate;

  @override
  State<FeedDistributionScreen> createState() => _FeedDistributionScreenState();
}

/// RATE_UNITS: (key, label, grams per unit).
const rateUnits = [
  ('g_bird', 'g per bird per day', 1.0),
  ('kg_bird', 'kg per bird per day', 1000.0),
  ('kg_100', 'kg per 100 birds per day', 10.0),
  ('kg_1000', 'kg per 1,000 birds per day', 1.0),
  ('lb_bird', 'lb per bird per day', 453.59237),
  ('lb_100', 'lb per 100 birds per day', 4.5359237),
];
const defaultRateUnit = 'g_bird';

(String, String, double) _unitOf(String? u) =>
    rateUnits.firstWhere((x) => x.$1 == u, orElse: () => rateUnits.first);

String rateUnitLabel(String? u) => _unitOf(u).$2;

double _round(double v, double by) => (v * by).roundToDouble() / by;

/// toGramsPerBird: what was typed, in grams per bird per day.
double? toGramsPerBird(double? value, String? unit) =>
    value == null || !value.isFinite || value <= 0 ? null : _round(value * _unitOf(unit).$3, 1e6);

/// fromGramsPerBird: grams per bird per day shown in [unit].
double? fromGramsPerBird(double? grams, String? unit) =>
    grams == null || !grams.isFinite || grams <= 0 ? null : _round(grams / _unitOf(unit).$3, 1e6);

/// parseKg: a non-negative number to three decimals, or null.
double? parseKg(String? text) {
  final t = (text ?? '').trim();
  if (t.isEmpty) return null;
  final n = double.tryParse(t);
  if (n == null || !n.isFinite || n < 0) return null;
  return _round(n, 1000);
}

/// rowState.
String rowState(Map c) {
  final n = (c['recordCount'] as num?)?.toInt() ?? 0;
  if (n == 1) return 'ok';
  return n == 0 ? 'noRecord' : 'duplicate';
}

double? suggestedKgByRate(Object? birds, double? grams) {
  final b = (birds as num?)?.toDouble();
  if (b == null || grams == null || b <= 0 || grams <= 0) return null;
  return (b * grams).roundToDouble() / 1000;
}

String _kg(num? n) => n == null ? '—' : '${fmtNum(n, 3)} kg';

/// postBlocker.
String? postBlocker(double actual, double remaining, List<(String state, String actualText)> rows) {
  if (rows.any((r) => r.$2.trim().isNotEmpty && parseKg(r.$2) == null)) {
    return 'Fix the feed amounts that are not valid numbers.';
  }
  if (actual <= 0) return 'Enter feed for at least one flock.';
  if (remaining < 0) {
    return 'Not enough feed: ${fmtNum(remaining.abs(), 3)} kg more than is in stock. Stock cannot go negative.';
  }
  return null;
}

/// manualFeedWarning.
String? manualFeedWarning(Map c, double? actualKg) {
  final manual = (c['manualFeedKg'] as num?)?.toDouble();
  if (actualKg == null || actualKg == 0 || manual == null || manual <= 0) return null;
  return 'Has ${fmtNum(manual, 3)} kg typed without stock; posting replaces it with ${fmtNum(actualKg, 3)} kg from stock.';
}

class _FeedDistributionScreenState extends State<FeedDistributionScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this)..addListener(_onTab);

  String? _today;
  String? _date;
  List<Map<String, dynamic>> _items = const [];
  int? _itemId;
  Map<String, dynamic>? _avail;
  List<Map<String, dynamic>>? _cands;
  bool _loading = false;
  String? _error;
  String _basis = 'Rate';
  final _rate = TextEditingController();
  String _rateUnit = defaultRateUnit;
  bool _saveRate = false;
  final Map<int, TextEditingController> _actual = {};
  final Map<int, TextEditingController> _notes = {};
  bool _posting = false;
  String? _lastPosted;
  List<Map<String, dynamic>>? _history;
  int? _openDoc;
  final Map<int, List<Map<String, dynamic>>> _docLines = {};

  ApiClient get _client => widget.session.farmClient;
  String get _farm => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _rate.dispose();
    for (final c in [..._actual.values, ..._notes.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onTab() {
    if (_tabs.index == 1 && !_tabs.indexIsChanging && _history == null) _loadHistory();
  }

  Future<void> _init() async {
    final today = await companyToday(widget.session, widget.company);
    List<Map<String, dynamic>> items = const [];
    try {
      final res = await _client.get('/api/Poultry/raw-material-items', query: {'farmId': _farm});
      // Finished feed, the same set the production forms offer.
      items = [
        for (final i in LookupLoader.rowsIn(res))
          if (i is Map &&
              RegExp('finish', caseSensitive: false).hasMatch('${i['category'] ?? ''}') &&
              i['isActive'] != false)
            Map<String, dynamic>.from(i),
      ];
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _today = today;
      // ?date= opens a past day; today or later is today.
      final picked = toBusinessDate(widget.initialDate);
      _date = picked != null && picked.compareTo(today) < 0 ? picked : today;
      _items = items;
    });
  }

  TextEditingController _actualFor(int id) => _actual.putIfAbsent(id, TextEditingController.new);
  TextEditingController _notesFor(int id) => _notes.putIfAbsent(id, TextEditingController.new);

  Future<void> _load() async {
    final id = _itemId;
    if (id == null || _date == null) {
      setState(() {
        _avail = null;
        _cands = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Future.wait([
        _client.get('/api/Poultry/feed-distributions/availability', query: {'farmId': _farm, 'itemId': '$id'}),
        _client.get('/api/Poultry/feed-distributions/candidates',
            query: {'farmId': _farm, 'businessDate': _date, 'itemId': '$id', 'avgDays': '7'}),
      ]);
      if (!mounted) return;
      final avail = Map<String, dynamic>.from(r[0] as Map);
      final unit = rateUnits.any((u) => u.$1 == avail['rateUnit']) ? '${avail['rateUnit']}' : defaultRateUnit;
      final shown = fromGramsPerBird((avail['gramsPerBirdPerDay'] as num?)?.toDouble(), unit);
      setState(() {
        _avail = avail;
        _cands = [for (final c in LookupLoader.rowsIn(r[1])) if (c is Map) Map<String, dynamic>.from(c)];
        _rateUnit = unit;
        _rate.text = shown == null ? '' : fmtNum(shown, 6).replaceAll(',', '');
        _saveRate = false;
        for (final c in [..._actual.values, ..._notes.values]) {
          c.clear();
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : 'Could not load this feed.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadHistory() async {
    try {
      final res = await _client.get('/api/Poultry/feed-distributions', query: {'farmId': _farm});
      if (mounted) {
        setState(() => _history = [for (final h in LookupLoader.rowsIn(res)) if (h is Map) Map<String, dynamic>.from(h)]);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load distributions. ${e.message}')));
      }
    }
  }

  double? get _grams => toGramsPerBird(double.tryParse(_rate.text.trim()), _rateUnit);

  /// Switching unit keeps the same physical rate: 112.5 g/bird becomes
  /// 11.25 kg/100 birds.
  void _changeUnit(String? next) {
    if (next == null) return;
    final converted = fromGramsPerBird(_grams, next);
    setState(() {
      _rateUnit = next;
      if (converted != null) _rate.text = fmtNum(converted, 6).replaceAll(',', '');
    });
  }

  List<({Map<String, dynamic> c, String state, double? suggested, String actualText})> get _rows => [
        for (final c in _cands ?? const <Map<String, dynamic>>[])
          (
            c: c,
            state: rowState(c),
            suggested: _basis == 'RecentAverage'
                ? (c['recentAvgKg'] as num?)?.toDouble()
                : suggestedKgByRate(c['birds'], _grams),
            actualText: _actualFor((c['flockId'] as num).toInt()).text,
          ),
      ];

  void _fillFromSuggestions() {
    setState(() {
      _lastPosted = null;
      for (final r in _rows) {
        if (r.state == 'ok' && r.suggested != null) {
          _actualFor((r.c['flockId'] as num).toInt()).text = fmtNum(r.suggested, 3).replaceAll(',', '');
        }
      }
    });
  }

  Future<void> _confirmPost(double actual, int flockCount) async {
    final avail = _avail!;
    final docNotes = await showDialog<String>(
      context: context,
      builder: (_) => _PostDialog(
        summary: '${_kg(actual)} of ${avail['itemName']} on ${formatLongDate(_date)}, to $flockCount flocks. Stock is '
            "checked again when you post. Each flock's production record gets the feed as a stock line.",
      ),
    );
    if (docNotes != null) await _post(actual, docNotes);
  }

  Future<void> _post(double actualTotal, String docNotes) async {
    final avail = _avail!;
    setState(() => _posting = true);
    final messenger = ScaffoldMessenger.of(context);
    final lines = [
      for (final r in _rows)
        if (r.state == 'ok' && (parseKg(r.actualText) ?? 0) > 0)
          {
            'flockId': r.c['flockId'],
            'actualKg': parseKg(r.actualText),
            'suggestedKg': r.suggested,
            'birds': r.c['birds'],
            'notes': _notesFor((r.c['flockId'] as num).toInt()).text.trim().isEmpty
                ? null
                : _notesFor((r.c['flockId'] as num).toInt()).text.trim(),
          },
    ];
    final anySuggestion = lines.any((l) => l['suggestedKg'] != null);
    final grams = _grams;
    try {
      await _client.post('/api/Poultry/feed-distributions', body: {
        'farmId': _farm,
        'businessDate': _date,
        'itemId': _itemId,
        'basis': anySuggestion ? _basis : 'Manual',
        'gramsPerBirdPerDay': _basis == 'Rate' ? grams : null,
        'rateUnit': _basis == 'Rate' && grams != null ? _rateUnit : null,
        'saveRate': _basis == 'Rate' && _saveRate && grams != null,
        'notes': docNotes.isEmpty ? null : docNotes,
        'lines': lines,
      });
      final summary =
          '${_kg(actualTotal)} of ${avail['itemName']} to ${lines.length} flock${lines.length == 1 ? '' : 's'}';
      messenger.showSnackBar(SnackBar(content: Text('Feed distributed. $summary.')));
      setState(() => _lastPosted = 'Posted: $summary.');
      await _load();
      if (_history != null) _loadHistory();
    } on ApiException catch (e) {
      // 409: not enough feed — reload so the page shows what is there now.
      messenger.showSnackBar(SnackBar(content: Text('${e.statusCode == 409 ? 'Not enough feed' : 'Not posted'}. ${e.message}')));
      if (e.statusCode == 409) await _load();
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _toggleDoc(int id) async {
    if (_openDoc == id) {
      setState(() => _openDoc = null);
      return;
    }
    setState(() => _openDoc = id);
    if (!_docLines.containsKey(id)) {
      _docLines[id] = const [];
      try {
        final res = await _client.get('/api/Poultry/feed-distributions/$id/lines', query: {'farmId': _farm});
        if (mounted) {
          setState(() => _docLines[id] = [for (final l in LookupLoader.rowsIn(res)) if (l is Map) Map<String, dynamic>.from(l)]);
        }
      } catch (_) {}
    }
  }

  Future<void> _reverse(Map h) async {
    final messenger = ScaffoldMessenger.of(context);
    final reason = await showReasonDialog(
      context,
      title: 'Reverse this feed distribution?',
      description: "The feed comes off each flock's production record and goes back into stock. The distribution "
          'stays in the history, marked Reversed.',
      confirmLabel: 'Reverse',
      destructive: true,
    );
    if (reason == null) return;
    try {
      await _client.post('/api/Poultry/feed-distributions/${h['poultryFeedDistributionId']}/reversal',
          body: {'farmId': _farm, 'reason': reason});
      messenger.showSnackBar(const SnackBar(
          content: Text("Distribution reversed. The feed went back into stock and off the flocks' records.")));
      await _loadHistory();
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Not reversed. ${e.message}')));
    }
  }

  void _openWeb(String label, String href) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WebPageScreen(label: label, href: href, company: widget.company, session: widget.session),
      ));

  Future<void> _pickDate() async {
    final today = businessDateAsDateTime(_today) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: businessDateAsDateTime(_date) ?? today,
      firstDate: DateTime(today.year - 5),
      lastDate: today,
    );
    if (d == null) return;
    setState(() {
      _lastPosted = null;
      _date = isoDay(d);
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-feed-distribution');
    return Scaffold(
      appBar: AppBar(
        leading: lead.leading,
        leadingWidth: lead.width,
        title: const Text('Distribute Feed'),
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Distribute'), Tab(text: 'Posted distributions')]),
      ),
      body: TabBarView(controller: _tabs, children: [_distribute(), _historyTab()]),
    );
  }

  Widget _distribute() {
    final tokens = context.tokens;
    final avail = _avail;
    final rows = _rows;
    final available = (avail?['availableKg'] as num?)?.toDouble() ?? 0;
    final suggested = _round(rows.fold(0.0, (a, r) => a + (r.state == 'ok' ? r.suggested ?? 0 : 0)), 1000);
    final actual = _round(rows.fold(0.0, (a, r) => a + (r.state == 'ok' ? parseKg(r.actualText) ?? 0 : 0)), 1000);
    final remaining = _round(available - actual, 1000);
    final blocker = postBlocker(actual, remaining, [for (final r in rows) (r.state, r.actualText)]);
    final nothingEntered = rows.every((r) => r.actualText.trim().isEmpty);
    final eligible = rows.where((r) => r.state == 'ok').length;
    final feeding = rows.where((r) => r.state == 'ok' && (parseKg(r.actualText) ?? 0) > 0).length;
    final grams = _grams;
    final recognition = avail?['costRecognitionMethod'] == 'EXPENSE_WHEN_CONSUMED'
        ? 'Expensed when consumed — posting records the feed cost as an expense.'
        : 'Expensed when purchased — posting moves stock only; the cost was expensed at purchase.';
    TextStyle muted([double s = 12]) => TextStyle(fontSize: s, color: tokens.mutedForeground);

    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
          children: [
            Text(
              'Give one feed to many flocks at once. Each flock gets the feed on its production record for the day, '
              'exactly as if entered one by one.',
              style: muted(13),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Business date', style: muted()),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: _today == null ? null : _pickDate,
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(_date == null ? 'Loading…' : formatLongDate(_date)),
                ),
                const SizedBox(height: 10),
                Text('Feed product', style: muted()),
                const SizedBox(height: 4),
                AppSelect<String>(
                  value: _itemId?.toString(),
                  hintText: _items.isNotEmpty ? 'Choose feed' : 'No finished feed items',
                  items: [
                    for (final i in _items)
                      AppSelectItem(value: '${i['poultryRawMaterialItemId']}', label: '${i['itemName'] ?? ''}'),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _lastPosted = null;
                      _itemId = int.tryParse(v ?? '');
                    });
                    _load();
                  },
                ),
                const SizedBox(height: 10),
                Text('Source', style: muted()),
                const SizedBox(height: 4),
                Text(
                  avail == null
                      ? '—'
                      : '${avail['lotCount']} stock lot${avail['lotCount'] == 1 ? '' : 's'} · ${avail['usageMethod']}',
                ),
              ]),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Color(0xFF9F1239)))
            else if (_loading)
              const Row(children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Loading flocks…'),
              ])
            else if (_itemId == null)
              Text('Choose a feed product to see the flocks for ${formatLongDate(_date)}.', style: muted(13))
            else if (avail != null && _cands != null) ...[
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Suggest by', style: muted()),
                  const SizedBox(height: 4),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'Rate', label: Text('Feed rate')),
                      ButtonSegment(value: 'RecentAverage', label: Text('Recent average (7 days)')),
                    ],
                    selected: {_basis},
                    onSelectionChanged: (s) => setState(() => _basis = s.first),
                  ),
                  if (_basis == 'Rate') ...[
                    const SizedBox(height: 10),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: 110,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Feed rate', style: muted()),
                          const SizedBox(height: 4),
                          AppNumberInput(controller: _rate, allowDecimal: true, onChanged: (_) => setState(() {})),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Unit', style: muted()),
                          const SizedBox(height: 4),
                          AppSelect<String>(
                            value: _rateUnit,
                            items: [for (final u in rateUnits) AppSelectItem(value: u.$1, label: u.$2)],
                            onChanged: _changeUnit,
                          ),
                        ]),
                      ),
                    ]),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _saveRate,
                      onChanged: grams == null ? null : (v) => setState(() => _saveRate = v == true),
                      title: const Text("Save as this feed's rate", style: TextStyle(fontSize: 14)),
                    ),
                    if (grams == null)
                      Text(
                        'No feed rate is set for ${avail['itemName']}. Type the farm\'s own rate, in whichever unit you '
                        'use, to get suggestions — none is assumed.',
                        style: muted(),
                      ),
                  ],
                  const SizedBox(height: 8),
                  AppButton(
                    label: 'Fill Actual from suggestions',
                    variant: AppButtonVariant.outline,
                    size: AppButtonSize.sm,
                    onPressed: rows.any((r) => r.state == 'ok' && r.suggested != null) ? _fillFromSuggestions : null,
                  ),
                  const SizedBox(height: 10),
                  _StatGrid(stats: [
                    ('Available inventory', _kg(available), null),
                    ('Suggested total', _kg(suggested), null),
                    ('Actual distribution', _kg(actual), null),
                    ('Remaining inventory', _kg(remaining), remaining < 0 ? const Color(0xFFBE123C) : null),
                  ]),
                  const SizedBox(height: 6),
                  Text(recognition, style: muted()),
                ]),
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                Text('No active flocks are expected to report on this date.', style: muted(13)),
              for (final r in rows) ...[_flockCard(r), const SizedBox(height: 8)],
            ],
          ],
        ),
      ),
      if (avail != null && _cands != null && !_loading)
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(color: tokens.card, border: Border(top: BorderSide(color: tokens.border))),
          child: SafeArea(
            top: false,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_lastPosted != null && nothingEntered)
                Wrap(children: [
                  Text('$_lastPosted ', style: const TextStyle(fontSize: 13, color: Color(0xFF047857))),
                  InkWell(
                    onTap: () => _tabs.animateTo(1),
                    child: const Text('View in Posted distributions',
                        style: TextStyle(fontSize: 13, color: Color(0xFF047857), decoration: TextDecoration.underline)),
                  ),
                ])
              else if (nothingEntered)
                Text("Type the feed amounts for the flocks you're feeding.", style: muted(13))
              else
                Text(
                  blocker ?? '${_kg(actual)} to $feeding of $eligible flocks · ${_kg(remaining)} left',
                  style: TextStyle(fontSize: 13, color: blocker != null ? const Color(0xFFBE123C) : tokens.mutedForeground),
                ),
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669), minimumSize: const Size.fromHeight(46)),
                onPressed: blocker != null || _posting ? null : () => _confirmPost(actual, feeding),
                child: Text(_posting ? 'Posting…' : 'Post Feed Distribution'),
              ),
            ]),
          ),
        ),
    ]);
  }

  Widget _flockCard(({Map<String, dynamic> c, String state, double? suggested, String actualText}) r) {
    final tokens = context.tokens;
    final c = r.c;
    final id = (c['flockId'] as num).toInt();
    final locked = r.state != 'ok';
    final warn = manualFeedWarning(c, parseKg(r.actualText));
    final invalid = r.actualText.trim().isNotEmpty && parseKg(r.actualText) == null;
    final thisItem = (c['thisItemKg'] as num?) ?? 0;
    final avgDays = (c['recentAvgDays'] as num?)?.toInt();
    TextStyle muted([double s = 12]) => TextStyle(fontSize: s, color: tokens.mutedForeground);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: locked ? tokens.muted : tokens.card,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${c['flockName'] ?? ''}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        if (thisItem > 0) Text('Already ${_kg(thisItem)} of this feed today', style: muted()),
        if (warn != null) Text('⚠ $warn', style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
        const SizedBox(height: 4),
        Text('House/Pen: ${c['houseName'] ?? '—'} · Current birds: ${c['birds'] == null ? '—' : fmtNum(c['birds'] as num, 0)}',
            style: muted()),
        Text(
          'Suggested feed: ${locked ? '—' : _kg(r.suggested)}'
          '${!locked && _basis == 'RecentAverage' && avgDays != null && avgDays > 0 ? ' (avg of $avgDays day${avgDays == 1 ? '' : 's'})' : ''}',
          style: muted(),
        ),
        const SizedBox(height: 8),
        if (locked)
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Icon(Icons.lock_outline, size: 15),
            const SizedBox(width: 4),
            if (r.state == 'noRecord') ...[
              const Text('No production record — ', style: TextStyle(fontSize: 12)),
              InkWell(
                onTap: () => _openWeb('Record production', '/production-records/new?flockId=$id&date=$_date'),
                child: const Text('record it first',
                    style: TextStyle(fontSize: 12, color: Color(0xFF0369A1), decoration: TextDecoration.underline)),
              ),
            ] else ...[
              Text('${c['recordCount']} records for this day — ', style: const TextStyle(fontSize: 12)),
              InkWell(
                onTap: () => _openWeb('Production records', '/production-records?date=$_date'),
                child: const Text('fix the duplicate',
                    style: TextStyle(fontSize: 12, color: Color(0xFF0369A1), decoration: TextDecoration.underline)),
              ),
            ],
          ])
        else
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 130,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Actual feed (kg)', style: muted()),
                const SizedBox(height: 4),
                AppNumberInput(
                  key: ValueKey('actual-$id'),
                  controller: _actualFor(id),
                  allowDecimal: true,
                  onChanged: (_) => setState(() => _lastPosted = null),
                ),
                if (invalid) const Text('Not a valid number', style: TextStyle(fontSize: 11, color: Color(0xFFBE123C))),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Notes', style: muted()),
                const SizedBox(height: 4),
                AppInput(controller: _notesFor(id)),
              ]),
            ),
          ]),
      ]),
    );
  }

  Widget _historyTab() {
    final tokens = context.tokens;
    final history = _history;
    if (history == null) return const Center(child: CircularProgressIndicator());
    if (history.isEmpty) {
      return Center(child: Text('No feed has been distributed yet.', style: TextStyle(color: tokens.mutedForeground)));
    }
    TextStyle muted([double s = 12]) => TextStyle(fontSize: s, color: tokens.mutedForeground);
    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
        children: [
          for (final h in history) ...[
            Builder(builder: (context) {
              final id = (h['poultryFeedDistributionId'] as num).toInt();
              final open = _openDoc == id;
              final posted = h['status'] == 'Posted';
              return AppCard(
                onTap: () => _toggleDoc(id),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: tokens.mutedForeground),
                    const SizedBox(width: 4),
                    Expanded(child: Text(formatLongDate(h['businessDate']), style: const TextStyle(fontWeight: FontWeight.w600))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: posted ? const Color(0xFFD1FAE5) : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('${h['status']}',
                          style: TextStyle(fontSize: 12, color: posted ? const Color(0xFF047857) : const Color(0xFF475569))),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text('${h['itemName'] ?? '—'} · ${h['flockCount']} flocks · ${_kg(h['totalActualKg'] as num?)}'
                      '${h['totalCost'] != null ? ' · ${ghc(h['totalCost'] as num)}' : ''}', style: muted(13)),
                  if (posted) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: AppButton(
                        label: 'Reverse',
                        icon: Icons.undo,
                        variant: AppButtonVariant.outline,
                        size: AppButtonSize.sm,
                        onPressed: () => _reverse(h),
                      ),
                    ),
                  ],
                  if (open) ...[
                    const Divider(height: 16),
                    Text(
                      'Posted by ${h['postedBy'] ?? 'unknown'} · ${'${h['postedAtUtc'] ?? ''}'.replaceFirst('T', ' ').split('.').first}'
                      '${h['basis'] != 'Manual' ? ' · suggested by ${h['basis'] == 'Rate' ? 'rate ${fmtNum(fromGramsPerBird((h['gramsPerBirdPerDay'] as num?)?.toDouble(), '${h['rateUnit'] ?? defaultRateUnit}'), 6)} ${rateUnitLabel('${h['rateUnit'] ?? defaultRateUnit}')}' : 'recent average'}' : ''}'
                      '${h['notes'] != null ? ' · “${h['notes']}”' : ''}',
                      style: muted(),
                    ),
                    if (h['status'] == 'Reversed')
                      Text('Reversed by ${h['reversedBy'] ?? 'unknown'} · ${'${h['reversedAtUtc'] ?? ''}'.replaceFirst('T', ' ').split('.').first} — ${h['reversalReason'] ?? ''}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFFBE123C))),
                    const SizedBox(height: 6),
                    for (final l in _docLines[id] ?? const <Map<String, dynamic>>[])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          '${l['flockName'] ?? ''} — ${_kg(l['actualKg'] as num?)}'
                          '${l['suggestedKg'] != null ? ' (suggested ${_kg(l['suggestedKg'] as num?)})' : ''}'
                          '${l['totalCost'] != null ? ' · ${ghc(l['totalCost'] as num)}' : ''}'
                          '${'${l['notes'] ?? ''}'.isNotEmpty ? ' · ${l['notes']}' : ''}'
                          '${l['reversalNote'] != null ? ' · ${l['reversalNote']}' : ''}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                  ],
                ]),
              );
            }),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});
  final List<(String, String, Color?)> stats;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 8) / 2;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (label, value, color) in stats)
          Container(
            width: w,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(border: Border.all(color: tokens.border), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label.toUpperCase(), style: TextStyle(fontSize: 10.5, letterSpacing: .4, color: tokens.mutedForeground)),
              Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
            ]),
          ),
      ]);
    });
  }
}

/// "Post feed distribution?" with optional notes. Completes with the trimmed
/// notes, or null when cancelled; owns its controller so closing cannot use
/// a disposed one.
class _PostDialog extends StatefulWidget {
  const _PostDialog({required this.summary});
  final String summary;

  @override
  State<_PostDialog> createState() => _PostDialogState();
}

class _PostDialogState extends State<_PostDialog> {
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Post feed distribution?'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.summary, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 12),
        const Text('Notes (optional)', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        AppInput(controller: _notes, hintText: 'e.g. Morning feeding'),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
          onPressed: () => Navigator.pop(context, _notes.text.trim()),
          child: const Text('Post'),
        ),
      ],
    );
  }
}
