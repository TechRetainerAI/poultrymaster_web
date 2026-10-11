// The production record form (components/production/production-record-form.tsx),
// its modal (production-record-modal.tsx), the full pages
// (app/production-records/new and [id]) and the catch-up flow
// (production-catch-up-flow.tsx).

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../shared/business_dates.dart';
import '../reports/dashboard_screen.dart' show latestRecordForFlock, birdsLeftFromRecord;
import '../reports/report_routes.dart' show openAppHref;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, loc;
import '../trackers/tracker_widgets.dart';
import 'production_logic.dart';
import 'production_widgets.dart';

const feedTypes = ['Starter Feed', 'Grower Feed', 'Layer Feed', 'Broiler Feed', 'Organic Feed', 'Custom Mix'];

/// What the host shows around the form (the modal header and footer).
class ProductionFormStatus {
  const ProductionFormStatus({
    this.dirty = false,
    this.saving = false,
    this.loading = false,
    this.flockName,
    this.date = '',
    this.totalEggs = 0,
    this.crates = 0,
    this.pieces = 0,
    this.netSellable = 0,
    this.deaths = 0,
    this.birdsLeft = 0,
    this.feedCost = 0,
  });
  final bool dirty, saving, loading;
  final String? flockName;
  final String date;
  final num totalEggs, netSellable, deaths, birdsLeft, feedCost;
  final int crates, pieces;
}

class ProductionRecordForm extends StatefulWidget {
  const ProductionRecordForm({
    super.key,
    required this.session,
    required this.company,
    this.recordId,
    this.flockId,
    this.date,
    this.initialFeedLines,
    this.initialMedLines,
    this.hideActions = false,
    this.onSaved,
    this.onCancel,
    this.onStatus,
  });
  final Session session;
  final Company company;

  /// Set when editing.
  final int? recordId;
  final int? flockId;
  final String? date;
  final List<ConsumptionLine>? initialFeedLines, initialMedLines;
  final bool hideActions;
  final void Function(int? id, Map<String, Object?> input)? onSaved;
  final VoidCallback? onCancel;
  final ValueChanged<ProductionFormStatus>? onStatus;

  @override
  State<ProductionRecordForm> createState() => ProductionRecordFormState();
}

class ProductionRecordFormState extends State<ProductionRecordForm> {
  bool get _edit => widget.recordId != null;
  bool _saving = false, _loading = false, _dirty = false, _flocksLoading = true, _hydrated = false;
  String _error = '', _flocksError = '';
  List<Map> _flocks = [], _batches = [], _rawItems = [], _purchases = [];
  String _batch = 'ALL';
  int? _keepFlockId;
  PickSettings _picks = const PickSettings();
  Map? _loaded;

  String _flockId = '', _date = '', _eggGrade = eggGradeNone, _feedType = '';
  final _broken = TextEditingController(), _meaty = TextEditingController(), _soft = TextEditingController(), _lost = TextEditingController();
  final _numBirds = TextEditingController(), _mortality = TextEditingController(), _medication = TextEditingController(), _notes = TextEditingController();
  final _manualWeeks = TextEditingController(), _manualDays = TextEditingController(), _manualYears = TextEditingController();
  String _feedKg = '';
  bool _manualAge = false;
  num? _previousBirdsLeft;
  String? _seededFor;

  /// Crates and loose per pick: first … sixth.
  final _crates = List<num>.filled(6, 0), _loose = List<num>.filled(6, 0);

  /// The saved totals per pick until the picks are touched (edit), as the web keeps them.
  final _pickTotals = List<num>.filled(6, 0);

  late final List<ConsumptionLine> _feedLines = _edit
      ? []
      : (widget.initialFeedLines?.isNotEmpty ?? false)
          ? [for (final l in widget.initialFeedLines!) ConsumptionLine(l.itemId, l.qty)]
          : [ConsumptionLine()];
  late final List<ConsumptionLine> _medLines = _edit
      ? []
      : (widget.initialMedLines?.isNotEmpty ?? false)
          ? [for (final l in widget.initialMedLines!) ConsumptionLine(l.itemId, l.qty)]
          : [ConsumptionLine(), ConsumptionLine()];
  ConsumptionCredit _feedCredit = {}, _medCredit = {};
  int _lineSeed = 0;

  ApiClient get _api => widget.session.farmClient;
  String get _userId => widget.session.tokens.userId ?? '';
  Map<String, String> get _ctx => {'userId': _userId, 'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    _flockId = widget.flockId != null ? '${widget.flockId}' : '';
    _date = (!_edit ? widget.date : null) ?? DateTime.now().toUtc().toIso8601String().substring(0, 10);
    _keepFlockId = _edit ? widget.flockId : null;
    _loading = _edit;
    _hydrated = !_edit;
    for (final c in _textControllers) {
      c.addListener(_markDirtyText);
    }
    PickSettings.load(widget.session, widget.company).then((p) {
      if (mounted) setState(() => _picks = p);
    });
    _loadLookups();
    if (_edit) _loadRecord();
    WidgetsBinding.instance.addPostFrameCallback((_) => _seed());
  }

  List<TextEditingController> get _textControllers =>
      [_broken, _meaty, _soft, _lost, _numBirds, _mortality, _medication, _notes, _manualWeeks, _manualDays, _manualYears];

  bool _silent = false;
  void _markDirtyText() {
    if (_silent || !mounted) return;
    setState(() => _dirty = true);
    _report();
  }

  @override
  void dispose() {
    for (final c in _textControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(VoidCallback f) {
    setState(() {
      f();
      _dirty = true;
    });
    _report();
  }

  Future<void> _loadLookups() async {
    Future<List<Map>> list(String path, Map<String, String> q) async {
      try {
        return rowsOf(await _api.get(path, query: q));
      } on ApiException {
        return <Map>[];
      }
    }

    final farm = {'farmId': widget.company.farmId};
    final r = await Future.wait([
      list('/api/Flock', _ctx),
      list('/api/MainFlockBatch', _ctx),
      list('/api/Poultry/raw-material-items', farm),
      list('/api/Poultry/raw-material-purchases', farm),
    ]);
    if (!mounted) return;
    setState(() {
      _flocks = r[0];
      _batches = r[1];
      _rawItems = r[2];
      _purchases = r[3];
      _flocksLoading = false;
      _flocksError = _flockOptions.isEmpty ? _emptyHint() : '';
    });
    _seed();
    _report();
  }

  String _emptyHint() {
    if (_flocks.isEmpty) return 'No flocks in the database for this farm. Add a flock on the Flocks page first.';
    if (!_flocks.any((f) => f['hasArrived'] == true)) {
      return 'You have ${_flocks.length} flock(s), but none are ready for production yet. On the Flocks page, turn on “Flock Has Arrived” (and keep the flock Active).';
    }
    return 'No flocks available';
  }

  /// useBatchFlockSelect({ excludeClosed, keepFlockId }).
  List<Map> get _flockOptions => [
        for (final f in _flocks)
          if ((tStr(f['closedDate']).isEmpty || tIntOrNull(f['flockId']) == _keepFlockId) &&
              (_batch == 'ALL' || tStr(f['batchId']) == _batch) &&
              f['flockId'] != null &&
              tStr(f['name']).isNotEmpty)
            f,
      ];

  Map? get _selectedFlock => _flocks.where((f) => tStr(f['flockId']) == _flockId).firstOrNull;

  /// The birds left last recorded for this flock before this date seed "Number of birds".
  Future<void> _seed() async {
    if (_flockId.isEmpty || _date.isEmpty) {
      if (mounted) setState(() => _previousBirdsLeft = null);
      return;
    }
    final flock = _flockId, date = _date;
    final switched = _seededFor != flock;
    void apply(num? v) {
      _seededFor = flock;
      _silent = true;
      if (switched) {
        _numBirds.text = v == null ? '' : '${v.toInt()}';
      } else if (_numBirds.text.isEmpty && v != null && v > 0) {
        _numBirds.text = '${v.toInt()}';
      }
      _silent = false;
    }

    try {
      final rows = rowsOf(await _api.get('/api/ProductionRecord', query: _ctx));
      if (!mounted || flock != _flockId || date != _date) return;
      final editing = widget.recordId ?? tIntOrNull(_loaded?['id']);
      final pool = [
        for (final r in rows)
          if ((editing == null || tIntOrNull(r['id']) != editing) && tStr(r['date']).padRight(10).substring(0, 10).compareTo(date) < 0) r,
      ];
      final latest = latestRecordForFlock(pool, int.parse(flock));
      setState(() {
        if (latest != null) {
          _previousBirdsLeft = birdsLeftFromRecord(latest);
          apply(_previousBirdsLeft);
        } else {
          final f = _selectedFlock;
          _previousBirdsLeft = f == null ? null : tNum(f['quantity']);
          apply(_previousBirdsLeft);
        }
      });
      _report();
    } on ApiException {
      if (mounted) setState(() => _previousBirdsLeft = null);
    }
  }

  Future<void> _loadRecord() async {
    try {
      final r = await _api.get('/api/ProductionRecord/${widget.recordId}', query: _ctx);
      final rec = r is Map && r['data'] is Map ? r['data'] as Map : r as Map;
      await _hydrate(rec);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : 'Could not load this production record.');
    } on TypeError {
      if (mounted) setState(() => _error = 'Could not load this production record.');
    }
    if (mounted) setState(() => _loading = false);
    _report();
  }

  Future<void> _hydrate(Map rec) async {
    final date = (DateTime.tryParse(tStr(rec['date']))?.toUtc().toIso8601String() ?? tStr(rec['date'])).split('T').first;
    _loaded = rec;
    _seededFor = rec['flockId'] != null ? tStr(rec['flockId']) : '';
    _keepFlockId = tIntOrNull(rec['flockId']);
    String n(Object? v) => v == null ? '' : tStr(v);
    _silent = true;
    _flockId = rec['flockId'] != null ? tStr(rec['flockId']) : '';
    _date = date;
    const keys = ['production9AM', 'production12PM', 'production4PM', 'production4thPick', 'production5thPick', 'production6thPick'];
    for (var i = 0; i < 6; i++) {
      final v = tNum(rec[keys[i]]);
      _pickTotals[i] = v;
      _crates[i] = v ~/ eggsPerCrate;
      _loose[i] = v % eggsPerCrate;
    }
    _broken.text = '${tNum(rec['brokenEggs']).toInt()}';
    _meaty.text = n(rec['meatyEggs']);
    _soft.text = n(rec['softEggs']);
    _lost.text = n(rec['lostEggs']);
    _feedKg = n(rec['feedKg']);
    _feedType = '';
    _mortality.text = n(rec['mortality']);
    _numBirds.text = n(rec['noOfBirds']);
    _notes.text = tStr(rec['notes']);
    _medication.text = tStr(rec['medication']);
    _eggGrade = eggGradeFromApi(rec['eggGrade']);
    _silent = false;

    final feeds = rowsOf(rec['feeds']);
    final meds = rowsOf(rec['medications']);
    final feedsForCredit = feeds.isNotEmpty
        ? feeds
        : rec['specificFeedUsedId'] != null
            ? [
                {'specificFeedUsedId': rec['specificFeedUsedId'], 'totalFeedConsumed': rec['totalFeedConsumed'], 'feedUnitCost': rec['feedUnitCost']},
              ]
            : <Map>[];
    final medsForCredit = meds.isNotEmpty
        ? meds
        : rec['specificMedicationUsedId'] != null
            ? [
                {
                  'specificMedicationUsedId': rec['specificMedicationUsedId'],
                  'totalMedicationConsumed': rec['totalMedicationConsumed'],
                  'medicationUnitCost': rec['medicationUnitCost'],
                },
              ]
            : <Map>[];
    _feedCredit = buildCredit(feedsForCredit, LineKeys.feed);
    _medCredit = buildCredit(medsForCredit, LineKeys.med);
    _feedLines
      ..clear()
      ..addAll([for (final f in feedsForCredit) ConsumptionLine(n(f['specificFeedUsedId']), n(f['totalFeedConsumed']))]);
    _medLines
      ..clear()
      ..addAll([for (final m in medsForCredit) ConsumptionLine(n(m['specificMedicationUsedId']), n(m['totalMedicationConsumed']))]);
    if (mounted) setState(() {});

    if (rec['flockId'] != null) {
      try {
        final usages = rowsOf(await _api.get('/api/FeedUsage', query: _ctx));
        final match = usages
            .where((u) =>
                tStr(u['flockId']) == tStr(rec['flockId']) &&
                (DateTime.tryParse(tStr(u['usageDate']))?.toUtc().toIso8601String() ?? '').startsWith(date))
            .firstOrNull;
        if (tStr(match?['feedType']).isNotEmpty && mounted) setState(() => _feedType = tStr(match!['feedType']));
      } on ApiException {
        // feed usage optional
      }
    }
    _hydrated = true;
    if (mounted) setState(() => _dirty = false);
  }

  // ------------------------------------------------------------ the figures

  List<Map> get _feedItems {
    final referenced = {for (final l in _feedLines) if (l.itemId.isNotEmpty) l.itemId};
    return [for (final i in _rawItems) if (isFinishedFeedCategory(i['category']) || referenced.contains(tStr(i['poultryRawMaterialItemId']))) i];
  }

  List<Map> get _medItems => [for (final i in _rawItems) if (isMedicationCategory(i['category'])) i];

  LinesComputed get _feed => computeLines(_feedLines, _feedItems, _purchases, _feedCredit, LineKeys.feed);
  LinesComputed get _med => computeLines(_medLines, _medItems, _purchases, _medCredit, LineKeys.med);

  /// Before the picks are touched on an edit, the saved totals stand.
  num _pick(int i) => _hydrated ? pickTotal(_crates[i], _loose[i]) : _pickTotals[i];
  num get _total => [for (var i = 0; i < 6; i++) _pick(i)].fold<num>(0, (a, b) => a + b);
  int _int(TextEditingController c) => int.tryParse(c.text) ?? 0;
  num get _losses => _int(_broken) + _int(_meaty) + _int(_soft) + _int(_lost);
  num get _birdsLeft => _int(_numBirds) - _int(_mortality);
  bool get _eggsOver => eggsExceedBirdsLeft(_total, _int(_numBirds) > 0 ? _birdsLeft : null);
  String get _eggsOverMessage =>
      '${loc(_total)} eggs against ${loc(_birdsLeft)} bird${_birdsLeft == 1 ? '' : 's'} left — more than one egg per bird. Check the crates and the bird count, or save anyway if that is right.';

  String? get _flockName => tStr(_selectedFlock?['name']).isNotEmpty ? tStr(_selectedFlock?['name']) : (tStr(_loaded?['flockName']).isNotEmpty ? tStr(_loaded?['flockName']) : null);

  void _report() {
    final c = cratesEquivalent(_total);
    widget.onStatus?.call(ProductionFormStatus(
      dirty: _dirty,
      saving: _saving,
      loading: _loading,
      flockName: _flockName,
      date: _date,
      totalEggs: _total,
      crates: c.crates,
      pieces: c.pieces,
      netSellable: netSellableEggs(_total, _losses),
      deaths: _int(_mortality),
      birdsLeft: _birdsLeft,
      feedCost: _feed.totalCost,
    ));
  }

  // ------------------------------------------------------------ save

  void _fail(String msg, {String title = 'Almost there'}) {
    setState(() => _error = msg);
    trackerToast(context, title, description: msg);
  }

  Future<void> submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = '';
    });
    _report();
    final numBirds = _int(_numBirds), mortality = _int(_mortality);
    final feed = _feed, med = _med;
    String? problem;
    if (mortality > numBirds) {
      _fail('Deaths ($mortality) cannot be greater than number of birds ($numBirds)', title: 'Double-check numbers');
      problem = 'x';
    } else if (numBirds - mortality < 0) {
      _fail('Birds left cannot be negative. Check your deaths and number of birds.', title: 'Double-check numbers');
      problem = 'x';
    } else if (_flockId.isEmpty) {
      _fail('Choose which flock this production entry is for.');
      problem = 'x';
    } else if (feed.firstShortfall != null) {
      _fail(
          'Not enough purchased stock tracked for "${tStr(feed.firstShortfall!.item?['itemName']).isEmpty ? 'this feed' : tStr(feed.firstShortfall!.item?['itemName'])}" to cover ${loc(feed.firstShortfall!.qty)} — record a new purchase first.');
      problem = 'x';
    } else if (med.firstShortfall != null) {
      _fail(
          'Not enough purchased stock tracked for "${tStr(med.firstShortfall!.item?['itemName']).isEmpty ? 'this medication' : tStr(med.firstShortfall!.item?['itemName'])}" to cover ${loc(med.firstShortfall!.qty)} — record a new purchase first.');
      problem = 'x';
    }
    if (problem != null) {
      setState(() => _saving = false);
      _report();
      return;
    }
    final calc = flockAge(_selectedFlock?['startDate'], _date);
    final age = resolveAge(_manualAge, (weeks: calc.weeks, days: calc.days),
        weeks: _manualWeeks.text, days: _manualDays.text, years: _manualYears.text);
    num? orNull(TextEditingController c) => c.text.isEmpty ? null : _int(c);
    final totalCost = round2(feed.totalCost + med.totalCost);
    final input = <String, Object?>{
      if (_edit) 'id': widget.recordId ?? tIntOrNull(_loaded?['id']),
      'farmId': widget.company.farmId,
      'userId': _userId,
      'createdBy': _userId,
      'updatedBy': _userId,
      'ageInWeeks': age.weeks,
      'ageInDays': age.days,
      'date': _date,
      'noOfBirds': numBirds,
      'mortality': mortality,
      'noOfBirdsLeft': numBirds - mortality,
      'feedKg': effectiveFeedKg(feed.totalConsumed, _feedKg),
      'medication': _medication.text.isEmpty ? 'None' : _medication.text,
      'production9AM': _pick(0),
      'production12PM': _pick(1),
      'production4PM': _pick(2),
      'production4thPick': _pick(3),
      'production5thPick': _pick(4),
      'production6thPick': _pick(5),
      'brokenEggs': _int(_broken),
      'totalProduction': _total,
      'FlockId': int.tryParse(_flockId),
      'eggGrade': eggGradeToApi(_eggGrade),
      'meatyEggs': orNull(_meaty),
      'softEggs': orNull(_soft),
      'lostEggs': orNull(_lost),
      'notes': _notes.text.isEmpty ? null : _notes.text,
      'specificFeedUsedId': null,
      'specificFeedUsedName': null,
      'feedUnitCost': null,
      'totalFeedConsumed': null,
      'totalFeedCost': null,
      'specificMedicationUsedId': null,
      'specificMedicationUsedName': null,
      'medicationUnitCost': null,
      'totalMedicationConsumed': null,
      'totalMedicationCost': null,
      'totalCostOfProduction': totalCost,
      'medications': med.lines,
      'feeds': feed.lines,
    };
    try {
      int? savedId;
      if (_edit) {
        final id = widget.recordId ?? tIntOrNull(_loaded?['id']);
        await _api.put('/api/ProductionRecord/$id', body: input);
        savedId = id;
      } else {
        await _api.post('/api/ProductionRecord', body: input);
      }
      if (!mounted) return;
      if (_eggsOver) trackerToast(context, 'Saved — check the egg count', description: _eggsOverMessage);
      setState(() {
        _dirty = false;
        _saving = false;
      });
      _report();
      widget.onSaved?.call(savedId, input);
      return;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : 'Failed to save');
    }
    if (mounted) setState(() => _saving = false);
    _report();
  }

  // ------------------------------------------------------------ build

  Widget _label(String t, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: t),
          if (required) const TextSpan(text: ' *', style: TextStyle(color: TColors.red600)),
        ]), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
      );

  Widget _gap(List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 12), children[i]],
      ]);

  Widget _pair(Widget a, Widget b) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: a),
        const SizedBox(width: 10),
        Expanded(child: b),
      ]);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(32), child: Text('Loading production record…', textAlign: TextAlign.center));
    }
    final total = _total;
    final crates = cratesEquivalent(total);
    final losses = _losses;
    final net = netSellableEggs(total, losses);
    final feed = _feed, med = _med;
    final feedCost = feed.totalCost, medCost = med.totalCost;
    final effFeed = effectiveFeedKg(feed.totalConsumed, _feedKg);
    final calcAge = flockAge(_selectedFlock?['startDate'], _date);
    final labels = _picks.labels;
    final pickRows = <(int, String)>[
      (0, labels.first),
      (1, labels.second),
      (2, labels.third),
      if (_picks.enableFourth || _pick(3) > 0) (3, labels.fourth),
      if (_picks.enableFifth || _pick(4) > 0) (4, labels.fifth),
      if (_picks.enableSixth || _pick(5) > 0) (5, labels.sixth),
    ];
    final flockChanged = _edit && _loaded?['flockId'] != null && _flockId.isNotEmpty && _flockId != tStr(_loaded!['flockId']);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_error.isNotEmpty) ...[TrackerBanner.error(_error), const SizedBox(height: 12)],
      if (_flocksError.isNotEmpty && _error.isEmpty) ...[TrackerBanner.warn(_flocksError), const SizedBox(height: 12)],
      ProdSection(
        title: 'Flock & Date',
        description: 'Which flock this record is for, and the day it covers.',
        accent: ProdAccent.sky,
        icon: Icons.calendar_month_outlined,
        child: _gap([
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _label('Batch'),
            AppSelect<String>(
              value: _batch,
              hintText: 'All batches',
              items: [
                const AppSelectItem(value: 'ALL', label: 'All batches'),
                for (final b in _batches)
                  if (b['batchId'] != null)
                    AppSelectItem(
                      value: tStr(b['batchId']),
                      label: tStr(b['batchName']).isNotEmpty
                          ? tStr(b['batchName'])
                          : (tStr(b['batchCode']).isNotEmpty ? tStr(b['batchCode']) : 'Batch #${b['batchId']}'),
                    ),
              ],
              onChanged: (v) => setState(() {
                _batch = v ?? 'ALL';
                if (_batch != 'ALL' && _flockId.isNotEmpty && !_flockOptions.any((f) => tStr(f['flockId']) == _flockId)) _flockId = '';
              }),
            ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _label('Flock', required: true),
            AppSelect<String>(
              value: _flockId.isEmpty ? null : _flockId,
              hintText: 'Select a flock',
              enabled: !_flocksLoading,
              items: [for (final f in _flockOptions) AppSelectItem(value: tStr(f['flockId']), label: tStr(f['name']))],
              onChanged: (v) {
                _set(() => _flockId = v ?? '');
                _seed();
              },
            ),
            if (flockChanged)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Moving this record to a different flock. Its eggs, deaths and feed/medication usage move with it — check the bird numbers below still make sense.',
                  style: TextStyle(fontSize: 12, color: TColors.amber700),
                ),
              ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _label('Date', required: true),
            AppDateField(
              value: businessDateAsDateTime(_date),
              onChanged: (v) {
                _set(() => _date = v == null ? '' : isoDay(v));
                _seed();
              },
            ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _label('Egg grade'),
            AppSelect<String>(
              value: _eggGrade,
              items: [for (final (v, l) in eggGradeOptions) AppSelectItem(value: v, label: l)],
              onChanged: (v) => _set(() => _eggGrade = v ?? eggGradeNone),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      ProdSection(
        title: 'Egg Production',
        description: 'Total = crates × 30 + loose eggs',
        badge: '${loc(total)} eggs',
        accent: ProdAccent.amber,
        icon: Icons.egg_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, label) in pickRows)
            Container(
              key: ValueKey('pick-$i'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: TColors.amber200), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.slate700)),
                const SizedBox(height: 6),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(child: ProdNumField(label: 'Crates', value: _crates[i], onChanged: (v) => _setPick(i, crates: v))),
                  const SizedBox(width: 8),
                  Expanded(child: ProdNumField(label: 'Loose eggs', value: _loose[i], onChanged: (v) => _setPick(i, loose: v))),
                  const SizedBox(width: 8),
                  Expanded(child: CalcField(label: 'Total eggs', value: loc(_pick(i)))),
                ]),
              ]),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xB3FEF3C7), border: Border.all(color: TColors.amber200), borderRadius: BorderRadius.circular(6)),
            child: Wrap(spacing: 24, runSpacing: 4, children: [
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Total picked eggs '),
                TextSpan(text: loc(total), style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.slate900)),
              ]), style: const TextStyle(fontSize: 14, color: TColors.slate500)),
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Crates equivalent '),
                TextSpan(
                  text: '${crates.crates} crate${crates.crates == 1 ? '' : 's'}${crates.pieces > 0 ? ' + ${crates.pieces} egg${crates.pieces == 1 ? '' : 's'}' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.slate900),
                ),
              ]), style: const TextStyle(fontSize: 14, color: TColors.slate500)),
            ]),
          ),
          if (_eggsOver) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: TColors.red50, border: Border.all(color: TColors.red300), borderRadius: BorderRadius.circular(6)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.warning_amber_outlined, size: 16, color: TColors.red700),
                const SizedBox(width: 8),
                Expanded(child: Text(_eggsOverMessage, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.red700))),
              ]),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 14),
      ProdSection(
        title: 'Egg Losses / Quality',
        description: 'Eggs that cannot be sold. Net sellable = total picked − these.',
        badge: losses > 0 ? '${loc(losses)} lost' : null,
        accent: ProdAccent.rose,
        icon: Icons.warning_amber_outlined,
        child: _gap([
          _pair(ProdTextField(label: 'Broken eggs', controller: _broken), ProdTextField(label: 'Meaty eggs', controller: _meaty)),
          _pair(ProdTextField(label: 'Soft eggs', controller: _soft), ProdTextField(label: 'Lost eggs', controller: _lost)),
          CalcField(label: 'Net sellable', value: loc(net), tone: CalcTone.good),
        ]),
      ),
      const SizedBox(height: 14),
      ProdSection(
        title: 'Birds & Age',
        description: _previousBirdsLeft != null ? 'Last recorded birds left for this flock: ${loc(_previousBirdsLeft!)}' : null,
        accent: ProdAccent.emerald,
        icon: Icons.flutter_dash,
        child: _gap([
          _pair(ProdTextField(label: 'Number of birds', controller: _numBirds), ProdTextField(label: 'Deaths', controller: _mortality)),
          CalcField(label: 'Birds left', value: loc(_birdsLeft), tone: _birdsLeft < 0 ? CalcTone.bad : null),
          if (_manualAge) ...[
            _pair(ProdTextField(label: 'Age (weeks)', controller: _manualWeeks), ProdTextField(label: 'Age (days)', controller: _manualDays)),
            ProdTextField(label: 'Age (years)', controller: _manualYears),
          ] else ...[
            _pair(CalcField(label: 'Age (weeks)', value: '${calcAge.weeks}'), CalcField(label: 'Age (days)', value: '${calcAge.days}')),
            CalcField(label: 'Age (years)', value: '${calcAge.years}'),
          ],
          InkWell(
            onTap: () => _set(() => _manualAge = !_manualAge),
            child: Row(children: [
              Checkbox(value: _manualAge, onChanged: (v) => _set(() => _manualAge = v ?? false)),
              const Flexible(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: 'Enter age manually '),
                  TextSpan(text: "(otherwise calculated from the flock's start date)", style: TextStyle(fontSize: 12, color: TColors.slate400)),
                ]), style: TextStyle(fontSize: 14, color: TColors.slate600)),
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      ProdSection(
        title: 'Feed',
        description: 'Draw feed from inventory as lines, or record a plain quantity.',
        badge: feedCost > 0 ? 'Cost ${feedCost.toStringAsFixed(2)}' : null,
        accent: ProdAccent.orange,
        icon: Icons.grass,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ConsumptionLines(
            lines: _feedLines,
            computed: feed,
            items: _feedItems,
            itemLabel: 'Specific Feed Used',
            placeholder: 'Select feed from inventory',
            emptyText: 'No feed lines. Click Add line to draw a feed from inventory.',
            noItemsText: 'No active Finished Feed items in Raw Materials.',
            removeLabel: 'Remove feed line',
            showIngredientTag: true,
            seed: _lineSeed,
            onAdd: () => _set(() {
              _feedLines.add(ConsumptionLine());
              _lineSeed++;
            }),
            onRemove: (i) => _set(() {
              _feedLines.removeAt(i);
              _lineSeed++;
            }),
            onChanged: () => _set(() {}),
          ),
          const Divider(height: 24),
          _label('Feed type'),
          AppSelect<String>(
            value: _feedType.isEmpty ? 'none' : _feedType,
            hintText: 'Select feed type',
            items: [const AppSelectItem(value: 'none', label: 'None'), for (final t in feedTypes) AppSelectItem(value: t, label: t)],
            onChanged: (v) => _set(() => _feedType = v == null || v == 'none' ? '' : v),
          ),
          const SizedBox(height: 12),
          CalcField(label: 'Total feed (kg)', value: loc(effFeed, 2)),
          const SizedBox(height: 4),
          Text(
            feed.totalConsumed > 0
                ? "Summed from the feed lines above, so it isn't counted twice."
                : effFeed > 0
                    ? "Carried over from this record's saved figure. Add a feed line above to change it."
                    : 'Add a feed line above to record feed.',
            style: const TextStyle(fontSize: 12, color: TColors.slate500),
          ),
          const SizedBox(height: 12),
          CalcField(label: 'Total feed cost', value: feedCost.toStringAsFixed(2)),
        ]),
      ),
      const SizedBox(height: 14),
      ProdSection(
        title: 'Medication',
        description: 'Medication drawn from inventory for this flock on this day.',
        badge: medCost > 0 ? 'Cost ${medCost.toStringAsFixed(2)}' : null,
        accent: ProdAccent.violet,
        icon: Icons.medication_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ConsumptionLines(
            lines: _medLines,
            computed: med,
            items: _medItems,
            itemLabel: 'Specific Medication Used',
            placeholder: 'Select medication from inventory',
            emptyText: 'No medication lines. Click Add line to draw a medication from inventory.',
            noItemsText: 'No active medication items in Raw Materials.',
            removeLabel: 'Remove medication line',
            seed: _lineSeed,
            onAdd: () => _set(() {
              _medLines.add(ConsumptionLine());
              _lineSeed++;
            }),
            onRemove: (i) => _set(() {
              _medLines.removeAt(i);
              _lineSeed++;
            }),
            onChanged: () => _set(() {}),
          ),
          const Divider(height: 24),
          _label('Medication notes'),
          AppInput(controller: _medication, hintText: 'e.g. Newcastle vaccine'),
          const SizedBox(height: 12),
          _pair(
            CalcField(label: 'Total medication consumed', value: loc(med.totalConsumed, 2)),
            CalcField(label: 'Total medication cost', value: medCost.toStringAsFixed(2)),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      ProdSection(
        title: 'Notes',
        description: 'Anything worth remembering about this day.',
        accent: ProdAccent.slate,
        icon: Icons.description_outlined,
        child: AppInput(controller: _notes, minLines: 3, maxLines: 5, hintText: 'Optional'),
      ),
      const SizedBox(height: 14),
      ProdSection(
        title: 'Summary',
        description: 'Check these before saving.',
        accent: ProdAccent.indigo,
        icon: Icons.balance,
        child: LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 16) / 2;
          Widget item(String l, String v, {bool strong = false}) => SizedBox(
                width: strong ? c.maxWidth : w,
                child: Container(
                  padding: const EdgeInsets.only(bottom: 4),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate200))),
                  child: Row(children: [
                    Expanded(child: Text(l, style: const TextStyle(fontSize: 13, color: TColors.slate500))),
                    Text(v, style: TextStyle(fontSize: 13, fontWeight: strong ? FontWeight.w600 : FontWeight.w400, color: TColors.slate900)),
                  ]),
                ),
              );
          return Wrap(spacing: 16, runSpacing: 8, children: [
            item('Total eggs', loc(total)),
            item('Total crates', '${crates.crates} + ${crates.pieces}'),
            item('Broken', loc(_int(_broken))),
            item('Meaty', loc(_int(_meaty))),
            item('Soft', loc(_int(_soft))),
            item('Lost', loc(_int(_lost))),
            item('Net sellable', loc(net)),
            item('Deaths', loc(_int(_mortality))),
            item('Birds left', loc(_birdsLeft)),
            item('Feed cost', feedCost.toStringAsFixed(2)),
            item('Medication cost', medCost.toStringAsFixed(2)),
            item('Total production cost', round2(feedCost + medCost).toStringAsFixed(2), strong: true),
          ]);
        }),
      ),
      if (!widget.hideActions) ...[
        const Divider(height: 28),
        Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
          if (widget.onCancel != null) OutlinedButton(onPressed: _saving ? null : widget.onCancel, child: const Text('Cancel')),
          FilledButton(
            onPressed: _saving ? null : submit,
            child: Text(_edit ? 'Update Production Record' : 'Save Production Record'),
          ),
        ]),
      ],
    ]);
  }

  void _setPick(int i, {num? crates, num? loose}) {
    _set(() {
      if (crates != null) _crates[i] = crates;
      if (loose != null) _loose[i] = loose;
      _hydrated = true;
    });
  }
}

// ------------------------------------------------------------ the modal

/// ProductionRecordModal: a sticky header (title, the flock and date, Open
/// Full Page, close), the form, and a footer with the running figures.
Future<bool?> showProductionRecordModal(BuildContext context, {required Session session, required Company company, Map? record, int? flockId}) =>
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProductionRecordModal(session: session, company: company, record: record, flockId: flockId),
    );

class _ProductionRecordModal extends StatefulWidget {
  const _ProductionRecordModal({required this.session, required this.company, this.record, this.flockId});
  final Session session;
  final Company company;
  final Map? record;
  final int? flockId;
  @override
  State<_ProductionRecordModal> createState() => _ProductionRecordModalState();
}

class _ProductionRecordModalState extends State<_ProductionRecordModal> {
  final _form = GlobalKey<ProductionRecordFormState>();
  ProductionFormStatus _s = const ProductionFormStatus();
  bool get _edit => widget.record != null;

  String get _fullHref => _edit
      ? '/production-records/${widget.record!['id']}'
      : '/production-records/new${widget.flockId != null ? '?flockId=${widget.flockId}' : ''}';

  Future<bool> _confirmDiscard(bool fullPage) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('You have unsaved changes'),
          content: Text(fullPage
              ? 'Opening the full page will discard the changes you have made here.'
              : 'Are you sure you want to close this form? Your changes will be lost.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(fullPage ? 'Discard and continue' : 'Discard changes')),
          ],
        ),
      ) ==
      true;

  Future<void> _close() async {
    if (_s.dirty && !await _confirmDiscard(false)) return;
    if (mounted) Navigator.pop(context, false);
  }

  Future<void> _fullPage() async {
    if (_s.dirty && !await _confirmDiscard(true)) return;
    if (!mounted) return;
    final nav = Navigator.of(context);
    nav.pop(false);
    openAppHref(nav.context, widget.session, widget.company, _fullHref, label: 'Production record');
  }

  @override
  Widget build(BuildContext context) {
    final contextLine = [if (_s.flockName != null) _s.flockName!, if (_s.date.isNotEmpty) formatLongDate(_s.date)].join(' • ');
    Widget stat(String l, String v, {Color? color}) => Text.rich(TextSpan(children: [
          TextSpan(text: '$l '),
          TextSpan(text: v, style: TextStyle(fontWeight: FontWeight.w700, color: color ?? TColors.slate900)),
        ]), style: const TextStyle(fontSize: 12, color: TColors.slate500));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: TColors.slate50,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: TColors.emerald100,
            titleSpacing: 12,
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_edit ? 'Edit Production Record' : 'Add Production Record',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: TColors.slate900)),
              Text(
                contextLine.isNotEmpty ? contextLine : (_edit ? 'Update production data' : 'Record daily egg production data for a flock'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: TColors.slate500),
              ),
            ]),
            actions: [
              IconButton(tooltip: 'Open full page', icon: const Icon(Icons.open_in_full, size: 18), onPressed: _fullPage),
              IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: _close),
            ],
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 24), children: [
            ProductionRecordForm(
              key: _form,
              session: widget.session,
              company: widget.company,
              recordId: _edit ? tIntOrNull(widget.record!['id']) : null,
              flockId: widget.flockId ?? (_edit ? tIntOrNull(widget.record!['flockId']) : null),
              hideActions: true,
              onStatus: (s) {
                if (mounted) setState(() => _s = s);
              },
              onSaved: (_, _) => Navigator.pop(context, true),
            ),
          ]),
          bottomNavigationBar: SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: TColors.slate200))),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (!_s.loading)
                  Wrap(spacing: 14, runSpacing: 2, children: [
                    stat('Total eggs', loc(_s.totalEggs)),
                    stat('Crates', '${_s.crates} + ${_s.pieces}'),
                    stat('Net sellable', loc(_s.netSellable), color: TColors.emerald700),
                    stat('Deaths', loc(_s.deaths), color: _s.deaths > 0 ? TColors.rose700 : null),
                    stat('Birds left', loc(_s.birdsLeft), color: _s.birdsLeft < 0 ? TColors.rose700 : null),
                    stat('Feed cost', _s.feedCost.toStringAsFixed(2)),
                  ]),
                const SizedBox(height: 8),
                Row(children: [
                  OutlinedButton(onPressed: _s.saving ? null : _close, child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _s.saving || _s.loading ? null : () => _form.currentState?.submit(),
                      child: Text(_edit ? 'Update Production Record' : 'Save Production Record'),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ full pages

/// app/production-records/new (with ?flockId=, ?date=, ?catchUp=1&asOf=) and
/// app/production-records/[id].
class ProductionRecordPage extends StatelessWidget {
  const ProductionRecordPage({super.key, required this.session, required this.company, this.recordId, this.flockId, this.date, this.catchUp = false, this.asOf});
  final Session session;
  final Company company;
  final int? recordId, flockId;
  final String? date, asOf;
  final bool catchUp;

  @override
  Widget build(BuildContext context) {
    final edit = recordId != null;
    final title = edit ? 'Edit Production Record' : (catchUp ? 'Catch up production' : 'Add Production Record');
    final sub = edit
        ? 'Update production data'
        : (catchUp ? 'Each missed day in turn, oldest first, saved as its own daily record' : 'Record daily egg production data for a flock');
    void back() => Navigator.of(context).maybePop();
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: TColors.emerald100, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.description_outlined, size: 20, color: TColors.emerald600),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
              Text(sub, style: const TextStyle(fontSize: 13, color: TColors.slate600)),
            ]),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: TColors.red600),
            onPressed: back,
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Close'),
          ),
        ]),
        const SizedBox(height: 16),
        if (catchUp && flockId != null)
          ProductionCatchUpFlow(session: session, company: company, flockId: flockId!, asOf: asOf)
        else
          ProductionRecordForm(
            session: session,
            company: company,
            recordId: recordId,
            flockId: flockId,
            date: date,
            onSaved: (_, _) => back(),
            onCancel: back,
          ),
      ]),
    );
  }
}

/// `/production-records/new?…` and `/production-records/{id}`.
Widget? productionRecordScreenForHref(String href, Session s, Company c) {
  final uri = Uri.tryParse(href);
  if (uri == null) return null;
  final q = uri.queryParameters;
  if (uri.path == '/production-records/new') {
    final fid = int.tryParse(q['flockId'] ?? '');
    final flockId = fid != null && fid > 0 ? fid : null;
    return ProductionRecordPage(
      session: s,
      company: c,
      flockId: flockId,
      date: toBusinessDate(q['date']),
      catchUp: q['catchUp'] == '1' && flockId != null,
      asOf: toBusinessDate(q['asOf']),
    );
  }
  final m = RegExp(r'^/production-records/(\d+)$').firstMatch(uri.path);
  if (m != null) return ProductionRecordPage(session: s, company: c, recordId: int.parse(m[1]!));
  return null;
}

// ------------------------------------------------------------ catch-up

class ProductionCatchUpFlow extends StatefulWidget {
  const ProductionCatchUpFlow({super.key, required this.session, required this.company, required this.flockId, this.asOf});
  final Session session;
  final Company company;
  final int flockId;
  final String? asOf;
  @override
  State<ProductionCatchUpFlow> createState() => _ProductionCatchUpFlowState();
}

class _ProductionCatchUpFlowState extends State<ProductionCatchUpFlow> {
  List<String>? _queue;
  List<Map> _pending = [];
  String? _error, _flockName;
  int _pos = 0;
  final _saved = <String>[], _skipped = <String>[];
  bool _carry = true, _saving = false;
  List<ConsumptionLine>? _carriedFeed, _carriedMed;
  /// A fresh form for each day, as the web keys it on the date.
  final _forms = <String, GlobalKey<ProductionRecordFormState>>{};

  String get _backHref => widget.asOf != null ? '/poultry-farm-completeness?date=${widget.asOf}' : '/poultry-farm-completeness';

  @override
  void initState() {
    super.initState();
    widget.session.farmClient.get('/api/ActivityChecks/production/missing-dates', query: {
      'farmId': widget.company.farmId,
      'flockId': '${widget.flockId}',
      'days': '30',
      if (widget.asOf != null) 'businessDate': widget.asOf!,
    }).then((d) {
      final dates = rowsOf(d is Map ? d['dates'] : null).reversed.toList();
      if (mounted) {
        setState(() {
          _pending = [for (final x in dates) if (x['pendingBatchRecordId'] != null) x];
          _queue = [for (final x in dates) if (x['pendingBatchRecordId'] == null) toBusinessDate(x['date'])!];
        });
      }
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e is ApiException && e.message.isNotEmpty ? e.message : 'Could not load the missing days.');
    });
  }

  void _href(String h) => openAppHref(context, widget.session, widget.company, h, label: 'Farm Completeness');

  String _missingHref(Map p) {
    final id = p['pendingBatchRecordId'];
    return tStr(p['pendingBatchStatus']) == 'Draft' ? '/batch-production-records/$id/edit' : '/batch-production-records/$id/allocate';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: TColors.rose50, border: Border.all(color: TColors.rose200), borderRadius: BorderRadius.circular(10)),
        child: Text(_error!, style: const TextStyle(fontSize: 14, color: TColors.rose800)),
      );
    }
    final queue = _queue;
    if (queue == null) return const Text('Finding the missed days…', style: TextStyle(color: TColors.slate500));
    final total = queue.length;
    final finished = _pos >= total;
    final pendingNote = _pending.isEmpty
        ? null
        : Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF0F9FF), border: Border.all(color: const Color(0xFFBAE6FD)), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Already in a batch entry that has not been posted — post it instead of entering these again:',
                  style: TextStyle(fontSize: 14, color: Color(0xFF0C4A6E))),
              Wrap(spacing: 12, children: [
                for (final p in _pending)
                  InkWell(
                    onTap: () => _href(_missingHref(p)),
                    child: Text('${formatWeekdayDate(p['date'])} (batch #${tStr(p['pendingBatchRecordId'])})',
                        style: const TextStyle(fontSize: 14, color: Color(0xFF0C4A6E), decoration: TextDecoration.underline)),
                  ),
              ]),
            ]),
          );
    if (total == 0 || finished) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ?pendingNote,
        TCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (total == 0)
              const Text('This flock has no days to enter in the last 30 days.', style: TextStyle(fontSize: 14, color: TColors.slate700))
            else
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.check_circle_outline, size: 20, color: TColors.emerald600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_saved.length} of $total day${total == 1 ? '' : 's'} recorded${_flockName != null ? ' for $_flockName' : ''}.'
                    '${_skipped.isNotEmpty ? ' ${_skipped.length} skipped (${_skipped.map(formatShortDate).join(', ')}) — still missing.' : ''}',
                    style: const TextStyle(fontSize: 14, color: TColors.slate800),
                  ),
                ),
              ]),
            const SizedBox(height: 10),
            FilledButton(onPressed: () => _href(_backHref), child: const Text('Back to Farm Completeness')),
          ]),
        ),
      ]);
    }
    final current = queue[_pos];
    final isLast = _pos >= total - 1;
    void next() => setState(() {
          _pos++;
          if (_pos >= total) {
            trackerToast(context, '${_saved.length} day${_saved.length == 1 ? '' : 's'} recorded',
                description: _skipped.isNotEmpty ? '${_skipped.length} skipped — still missing.' : null);
          }
        });
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ?pendingNote,
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(left: BorderSide(color: TColors.amber600, width: 4)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: 'Day ${_pos + 1} of $total — ${formatWeekdayDate(current)}'),
            if (_flockName != null) TextSpan(text: '  $_flockName', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: TColors.slate500)),
          ]), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: TColors.slate900)),
          InkWell(
            onTap: () => setState(() => _carry = !_carry),
            child: Row(children: [
              Checkbox(value: _carry, onChanged: (v) => setState(() => _carry = v == true)),
              const Flexible(
                child: Text("Start each day with the previous day's feed & medication", style: TextStyle(fontSize: 14, color: TColors.slate700)),
              ),
            ]),
          ),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final d in queue)
              Builder(builder: (_) {
                final st = _saved.contains(d) ? 'saved' : _skipped.contains(d) ? 'skipped' : d == current ? 'current' : 'todo';
                final (bg, border, fg) = switch (st) {
                  'saved' => (TColors.emerald50, TColors.emerald200, TColors.emerald800),
                  'skipped' => (TColors.slate100, TColors.slate200, TColors.slate500),
                  'current' => (TColors.amber100, TColors.amber300, TColors.amber900),
                  _ => (Colors.white, TColors.slate200, TColors.slate600),
                };
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(999)),
                  child: Text(formatShortDate(d),
                      style: TextStyle(
                        fontSize: 12,
                        color: fg,
                        fontWeight: st == 'current' ? FontWeight.w600 : FontWeight.w400,
                        decoration: st == 'skipped' ? TextDecoration.lineThrough : null,
                      )),
                );
              }),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      ProductionRecordForm(
        key: _forms.putIfAbsent(current, GlobalKey<ProductionRecordFormState>.new),
        session: widget.session,
        company: widget.company,
        flockId: widget.flockId,
        date: current,
        hideActions: true,
        initialFeedLines: _carry ? _carriedFeed : null,
        initialMedLines: _carry ? _carriedMed : null,
        onStatus: (s) {
          if (!mounted) return;
          if (s.saving != _saving || (s.flockName != null && s.flockName != _flockName)) {
            setState(() {
              _saving = s.saving;
              if (s.flockName != null) _flockName = s.flockName;
            });
          }
        },
        onSaved: (_, input) {
          _saved.add(current);
          List<ConsumptionLine> carry(Object? lines, LineKeys k) => [
                for (final l in rowsOf(lines))
                  if (l[k.id] != null && tNum(l[k.consumed]) > 0) ConsumptionLine(tStr(l[k.id]), tStr(l[k.consumed])),
              ];
          final f = carry(input['feeds'], LineKeys.feed), m = carry(input['medications'], LineKeys.med);
          _carriedFeed = f.isEmpty ? null : f;
          _carriedMed = m.isEmpty ? null : m;
          if (!isLast) trackerToast(context, '${formatWeekdayDate(current)} saved', description: 'Next: ${formatWeekdayDate(queue[_pos + 1])}');
          next();
        },
      ),
      const SizedBox(height: 14),
      Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
        TextButton(onPressed: _saving ? null : () => _href(_backHref), child: const Text('Stop')),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
            onPressed: _saving
                ? null
                : () {
                    _skipped.add(current);
                    next();
                  },
            icon: const Icon(Icons.skip_next, size: 16),
            label: const Text('Skip this day'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TColors.emerald600),
            onPressed: _saving ? null : () => _forms[current]?.currentState?.submit(),
            child: Text(isLast ? 'Save & finish' : 'Save & next missing day'),
          ),
        ]),
      ]),
    ]);
  }
}
