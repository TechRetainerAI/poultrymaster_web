// The batch production record form (components/production/
// batch-production-record-form.tsx), its modal (batch-production-record-
// modal.tsx) and the full pages (app/batch-production-records/new and
// [id]/edit).

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../reports/report_routes.dart' show openAppHref;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, loc;
import '../trackers/tracker_widgets.dart';
import 'batch_production_logic.dart';
import 'production_logic.dart';
import 'production_record_form.dart' show feedTypes;
import 'production_widgets.dart';

const _scopeAll = 'all', _scopeCustom = 'custom';

String _numStr(Object? v) => v == null ? '' : (v is num && v == v.roundToDouble() ? '${v.toInt()}' : tStr(v));

/// What the modal header and footer show.
class BatchFormStatus {
  const BatchFormStatus({
    this.dirty = false,
    this.saving = false,
    this.loading = false,
    this.scopeLabel,
    this.date = '',
    this.includedFlockCount = 0,
    this.totalEggs = 0,
    this.crates = 0,
    this.pieces = 0,
    this.netSellable = 0,
    this.deaths = 0,
    this.feedCost = 0,
  });
  final bool dirty, saving, loading;
  final String? scopeLabel;
  final String date;
  final int includedFlockCount, totalEggs, crates, pieces, deaths;
  final num netSellable, feedCost;
}

class BatchProductionRecordForm extends StatefulWidget {
  const BatchProductionRecordForm({
    super.key,
    required this.session,
    required this.company,
    this.recordId,
    this.prefill,
    this.hideActions = false,
    this.onSaved,
    this.onCancel,
    this.onStatus,
  });
  final Session session;
  final Company company;

  /// Set when editing.
  final int? recordId;

  /// Create only: the dashboard's "Complete Missing Production".
  final MissingProductionPrefill? prefill;
  final bool hideActions;
  final void Function(String status, int? recordId)? onSaved;
  final VoidCallback? onCancel;
  final ValueChanged<BatchFormStatus>? onStatus;
  @override
  State<BatchProductionRecordForm> createState() => BatchProductionRecordFormState();
}

class BatchProductionRecordFormState extends State<BatchProductionRecordForm> {
  bool get _edit => widget.recordId != null;
  late bool _loading = _edit;
  bool _saving = false, _dirty = false, _flocksLoaded = false, _hydrating = false;
  String _error = '';
  List<Map> _batches = [], _flocks = [], _rawItems = [], _purchases = [];
  List<String> _priorNames = [];
  PickSettings _picks = const PickSettings();

  MissingProductionPrefill? get _missing => !_edit && widget.prefill != null && widget.prefill!.flockIds.isNotEmpty ? widget.prefill : null;
  late String _scope = _missing != null ? _scopeCustom : _scopeAll;
  late final _name = TextEditingController(text: _missing != null ? 'Missing production – ${formatShortDate(_missing!.date)}' : '');
  final _nameFocus = FocusNode();
  late List<int> _selected = [...?_missing?.flockIds];
  late String _date = (!_edit ? widget.prefill?.date : null) ?? isoDay(DateTime.now().toUtc());
  String _eggGrade = eggGradeNone, _feedType = '';
  final _crates = List<num>.filled(6, 0), _loose = List<num>.filled(6, 0);
  final _broken = TextEditingController(), _meaty = TextEditingController(), _soft = TextEditingController(), _lost = TextEditingController();
  final _feedKg = TextEditingController(), _medication = TextEditingController(), _deaths = TextEditingController();
  final _birdsLeft = TextEditingController(), _notes = TextEditingController();
  late List<ConsumptionLine> _feedLines = _edit ? [] : [ConsumptionLine()];
  late List<ConsumptionLine> _medLines = _edit ? [] : [ConsumptionLine(), ConsumptionLine()];
  int _lineSeed = 0;

  ApiClient get _api => widget.session.farmClient;
  String get _userId => widget.session.tokens.userId ?? '';
  Map<String, String> get _ctx => {'userId': _userId, 'farmId': widget.company.farmId};

  List<TextEditingController> get _texts => [_name, _broken, _meaty, _soft, _lost, _feedKg, _medication, _deaths, _birdsLeft, _notes];

  @override
  void initState() {
    super.initState();
    for (final c in _texts) {
      c.addListener(_typed);
    }
    PickSettings.load(widget.session, widget.company).then((p) {
      if (mounted) setState(() => _picks = p);
    });
    _load();
  }

  @override
  void dispose() {
    for (final c in _texts) {
      c.dispose();
    }
    _nameFocus.dispose();
    super.dispose();
  }

  void _typed() {
    if (_hydrating || !mounted) return;
    setState(() => _dirty = true);
    _report();
  }

  void _set(VoidCallback f) {
    setState(() {
      f();
      _dirty = true;
    });
    _report();
  }

  Future<void> _load() async {
    Future<List<Map>> list(String path, Map<String, String> q) async {
      try {
        return rowsOf(await _api.get(path, query: q));
      } on ApiException {
        return <Map>[];
      }
    }

    final farm = {'farmId': widget.company.farmId};
    try {
      final r = await Future.wait([
        list('/api/MainFlockBatch', _ctx),
        list('/api/Flock', _ctx),
        list('/api/Poultry/raw-material-items', farm),
        list('/api/Poultry/raw-material-purchases', farm),
      ]);
      Object? rec;
      String? recError;
      if (_edit) {
        try {
          rec = await _api.get('/api/ProductionBatchRecord/${widget.recordId}', query: farm);
        } on ApiException catch (e) {
          recError = e.message;
        }
      }
      if (!mounted) return;
      _batches = r[0];
      _flocks = r[1];
      _rawItems = r[2];
      _purchases = r[3];
      if (!_edit) {
        final names = <String>{};
        for (final x in await list('/api/ProductionBatchRecord', _ctx)) {
          if (tStr(x['batchSelectionType']) == 'CustomBatch' && tStr(x['batchName']).trim().isNotEmpty) names.add(tStr(x['batchName']).trim());
        }
        _priorNames = names.toList();
      } else if (rec is! Map) {
        _error = recError != null && recError.isNotEmpty ? recError : 'Batch production record not found';
      } else {
        _hydrate(rec);
      }
    } catch (e) {
      _error = e is ApiException && e.message.isNotEmpty ? e.message : 'Failed to load';
    }
    if (!mounted) return;
    setState(() {
      _dirty = false;
      _loading = false;
      _flocksLoaded = true;
    });
    _report();
  }

  void _hydrate(Map r) {
    _hydrating = true;
    final t = tStr(r['batchSelectionType']);
    _scope = t == 'AllBatches' ? _scopeAll : (t == 'CustomBatch' ? _scopeCustom : tStr(r['selectedBirdBatchId']));
    _name.text = tStr(r['batchName']);
    _selected = [for (final f in listOf(r, 'includedFlocks')) tIntOrNull(f['flockId']) ?? 0];
    const keys = ['first', 'second', 'third', 'fourth', 'fifth', 'sixth'];
    for (var i = 0; i < 6; i++) {
      _crates[i] = tNum(r['${keys[i]}PickCrates']);
      _loose[i] = tNum(r['${keys[i]}PickLooseEggs']);
    }
    final d = tStr(r['productionDate']).split('T').first;
    _date = d.isNotEmpty ? d : _date;
    _broken.text = _numStr(r['brokenEggs']);
    _meaty.text = _numStr(r['meatyEggs']);
    _soft.text = _numStr(r['softEggs']);
    _lost.text = _numStr(r['lostEggs']);
    _feedType = tStr(r['feedType']);
    _feedKg.text = _numStr(r['feedKg']);
    _medication.text = tStr(r['medication']);
    _deaths.text = _numStr(r['deaths']);
    _birdsLeft.text = _numStr(r['birdsLeft']);
    _notes.text = tStr(r['notes']);
    _eggGrade = eggGradeFromApi(r['eggGrade']);
    final feeds = listOf(r, 'feeds'), meds = listOf(r, 'medications');
    _feedLines = feeds.isNotEmpty ? [for (final f in feeds) ConsumptionLine(tStr(f['itemId']), _numStr(f['qty']))] : [ConsumptionLine()];
    _medLines = meds.isNotEmpty ? [for (final m in meds) ConsumptionLine(tStr(m['itemId']), _numStr(m['qty']))] : [ConsumptionLine()];
    _lineSeed++;
    _hydrating = false;
  }

  // ------------------------------------------------------------ derived

  String get _selectionType => _scope == _scopeAll ? 'AllBatches' : (_scope == _scopeCustom ? 'CustomBatch' : 'SpecificBatch');
  bool get _specific => _selectionType == 'SpecificBatch';
  int? get _birdBatchId => _specific ? int.tryParse(_scope) : null;
  Map? get _specificBatch => _batches.where((b) => tIntOrNull(b['batchId']) == _birdBatchId).firstOrNull;
  List<Map> get _activeFlocks => [for (final f in _flocks) if (f['active'] == true) f];
  Set<int> get _missingIds => {...?_missing?.flockIds};
  int get _prefillMatched => _activeFlocks.where((f) => _missingIds.contains(tIntOrNull(f['flockId']))).length;

  List<Map> get _included {
    if (_selectionType == 'SpecificBatch') return [for (final f in _activeFlocks) if (tIntOrNull(f['batchId']) == _birdBatchId) f];
    if (_selectionType == 'AllBatches') return _activeFlocks;
    return [for (final f in _activeFlocks) if (_selected.contains(tIntOrNull(f['flockId']))) f];
  }

  List<Map> get _feedItems {
    final referenced = {for (final l in _feedLines) if (l.itemId.isNotEmpty) l.itemId};
    return [for (final i in _rawItems) if (isFinishedFeedCategory(i['category']) || referenced.contains(tStr(i['poultryRawMaterialItemId']))) i];
  }

  List<Map> get _medItems => [for (final i in _rawItems) if (isMedicationCategory(i['category'])) i];
  LinesComputed get _feed => computeLines(_feedLines, _feedItems, _purchases, const {}, LineKeys.feed);
  LinesComputed get _med => computeLines(_medLines, _medItems, _purchases, const {}, LineKeys.med);

  int _pick(int i) => pickTotal(_crates[i], _loose[i]);
  int get _total => [for (var i = 0; i < 6; i++) _pick(i)].fold(0, (a, b) => a + b);
  int _int(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
  int get _losses => _int(_broken) + _int(_meaty) + _int(_soft) + _int(_lost);
  int? get _birdsLeftEntered => _birdsLeft.text.isEmpty ? null : _int(_birdsLeft);
  bool get _eggsOver => eggsExceedBirdsLeft(_total, _birdsLeftEntered);
  String get _eggsOverMessage {
    final b = _birdsLeftEntered ?? 0;
    return '${loc(_total)} eggs against ${loc(b)} bird${b == 1 ? '' : 's'} left — more than one egg per bird. '
        'Check the crates and the birds left, or save anyway if that is right.';
  }

  ({int weeks, int days, int years}) get _age => _specific ? flockAge(_specificBatch?['startDate'], _date) : (weeks: 0, days: 0, years: 0);

  String? get _scopeLabel => _selectionType == 'AllBatches'
      ? 'All batches'
      : _selectionType == 'CustomBatch'
          ? (_name.text.trim().isNotEmpty ? _name.text.trim() : 'Custom batch')
          : (_specificBatch == null ? null : (_specificBatch!['batchName'] ?? _specificBatch!['batchCode'])?.toString());

  void _report() {
    final c = cratesEquivalent(_total);
    widget.onStatus?.call(BatchFormStatus(
      dirty: _dirty,
      saving: _saving,
      loading: _loading,
      scopeLabel: _scopeLabel,
      date: _date,
      includedFlockCount: _included.length,
      totalEggs: _total,
      crates: c.crates,
      pieces: c.pieces,
      netSellable: netSellableEggs(_total, _losses),
      deaths: _int(_deaths),
      feedCost: _feed.totalCost,
    ));
  }

  // ------------------------------------------------------------ save

  List<Map<String, Object?>> _usage(LinesComputed c) => [
        for (final r in c.rows)
          if (r.item != null && r.qty > 0)
            {
              'itemId': tIntOrNull(r.item!['poultryRawMaterialItemId']),
              'itemName': tStr(r.item!['itemName']),
              'qty': r.qty,
              'unitCost': r.preview.unitCost,
              'totalCost': round2(r.preview.totalCost ?? 0),
              'method': r.item!['usageMethod'],
            },
      ];

  /// handleSave: "PendingAllocation" (Log Batch Production) or "Draft".
  Future<void> save(String status) async {
    setState(() {
      _saving = true;
      _error = '';
    });
    _report();
    try {
      if (_userId.isEmpty || widget.company.farmId.isEmpty) throw ApiException(0, 'Missing user/farm context');
      if (_selectionType == 'CustomBatch' && _included.isEmpty) {
        setState(() {
          _error = 'Select at least one flock for the custom batch.';
          _saving = false;
        });
        _report();
        return;
      }
      final age = _age;
      final feed = _feed, med = _med;
      final feedCost = feed.totalCost, medCost = med.totalCost;
      int? opt(TextEditingController c) => c.text.isEmpty ? null : _int(c);
      const keys = ['first', 'second', 'third', 'fourth', 'fifth', 'sixth'];
      final input = <String, Object?>{
        if (_edit) 'id': widget.recordId,
        'farmId': widget.company.farmId,
        'userId': _userId,
        'createdBy': _userId,
        'updatedBy': _userId,
        'batchSelectionType': _selectionType,
        'selectedBirdBatchId': _specific ? _birdBatchId : null,
        'batchName': _name.text.trim().isEmpty ? null : _name.text.trim(),
        'productionDate': _date,
        'ageInWeeks': _specific ? age.weeks : null,
        'ageInDays': _specific ? age.days : null,
        'ageDisplay': _specific ? '${age.weeks}w ${age.days % 7}d' : 'Mixed',
        for (var i = 0; i < 6; i++) ...{
          '${keys[i]}PickCrates': _crates[i],
          '${keys[i]}PickLooseEggs': _loose[i],
          '${keys[i]}PickTotal': _pick(i),
        },
        'brokenEggs': opt(_broken),
        'meatyEggs': opt(_meaty),
        'softEggs': opt(_soft),
        'lostEggs': opt(_lost),
        'totalEggs': _total,
        'feedKg': effectiveFeedKg(feed.totalConsumed, _feedKg.text),
        'feedType': _feedType.isEmpty ? null : _feedType,
        'medication': _medication.text.trim().isEmpty ? null : _medication.text.trim(),
        'deaths': _int(_deaths),
        'birdsLeft': opt(_birdsLeft),
        'eggGrade': eggGradeToApi(_eggGrade),
        'totalFeedCost': round2(feedCost),
        'totalMedicationCost': round2(medCost),
        'totalCostOfProduction': round2(feedCost + medCost),
        'status': status,
        'notes': _notes.text.isEmpty ? null : _notes.text,
        'includedFlocks': [
          for (final f in _included) {'flockId': tIntOrNull(f['flockId']), 'flockName': f['name'], 'birdBatchId': tIntOrNull(f['batchId'])},
        ],
        'feeds': _usage(feed),
        'medications': _usage(med),
      };
      int? savedId = widget.recordId;
      if (_edit) {
        await _api.put('/api/ProductionBatchRecord/${widget.recordId}', body: input);
      } else {
        final res = await _api.post('/api/ProductionBatchRecord', body: input);
        savedId = res is Map ? tIntOrNull(res['id']) : null;
      }
      if (!mounted) return;
      if (status == 'PendingAllocation') {
        trackerToast(context, 'Saved as Pending Allocation',
            description:
                'This batch production record has been saved as Pending Allocation. It will not affect flock records, inventory, birds left, or production reports until allocation is completed.');
      } else {
        trackerToast(context, 'Saved as draft', description: 'This batch production record has been saved as a draft.');
      }
      if (_eggsOver) trackerToast(context, 'Check the egg count', description: _eggsOverMessage);
      setState(() {
        _dirty = false;
        _saving = false;
      });
      _report();
      widget.onSaved?.call(status, savedId);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message.isNotEmpty ? e.message : 'Failed to save batch production record';
        _saving = false;
      });
      _report();
    }
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

  Widget _info(String text) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, size: 14, color: TColors.slate500),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: TColors.slate500))),
        ]),
      );

  Widget _missingAlert() {
    final m = _missing!;
    final count = !_flocksLoaded ? m.flockIds.length : _prefillMatched;
    final left = m.flockIds.length - _prefillMatched;
    const b = TextStyle(fontWeight: FontWeight.w700);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: TColors.amber200), borderRadius: BorderRadius.circular(8)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.warning_amber_outlined, size: 16, color: TColors.amber600),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Completing missing production for '),
              TextSpan(text: '$count', style: b),
              TextSpan(text: ' flock${count == 1 ? '' : 's'} on '),
              TextSpan(text: formatShortDate(m.date), style: b),
              const TextSpan(text: '. They are pre-selected and marked below.'),
            ]), style: const TextStyle(fontSize: 14, color: Color(0xFF78350F))),
            const SizedBox(height: 4),
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Production is recorded when this batch is allocated and '),
              const TextSpan(text: 'posted', style: b),
              const TextSpan(text: '. “Log Batch Production” takes you straight to allocation to do that; “Save as Draft” does not clear the dashboard.'),
              if (_date != m.date)
                TextSpan(text: ' The date has been changed from ${formatShortDate(m.date)}; these flocks are only missing on that day.'),
              if (_flocksLoaded && _prefillMatched < m.flockIds.length)
                TextSpan(
                    text: ' $left flagged flock${left == 1 ? ' is' : 's are'} no longer active and${left == 1 ? ' was' : ' were'} left out.'),
            ]), style: const TextStyle(fontSize: 12, color: Color(0xFF78350F))),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 64),
        child: Text('Loading batch production record…', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
      );
    }
    final total = _total;
    final crates = cratesEquivalent(total);
    final losses = _losses;
    final net = netSellableEggs(total, losses);
    final feed = _feed, med = _med;
    final feedCost = feed.totalCost, medCost = med.totalCost;
    final effFeed = effectiveFeedKg(feed.totalConsumed, _feedKg.text);
    final age = _age;
    final included = _included;
    final labels = _picks.labels;
    final pickRows = <(int, String)>[
      (0, labels.first),
      (1, labels.second),
      (2, labels.third),
      if (_picks.enableFourth || _pick(3) > 0) (3, labels.fourth),
      if (_picks.enableFifth || _pick(4) > 0) (4, labels.fifth),
      if (_picks.enableSixth || _pick(5) > 0) (5, labels.sixth),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_error.isNotEmpty) ...[TrackerBanner.error(_error), const SizedBox(height: 12)],
      ProdSection(
        title: 'Batch & Date',
        description: 'Which flocks these totals cover, and the day they were collected.',
        badge: '${included.length} flock${included.length == 1 ? '' : 's'}',
        accent: ProdAccent.sky,
        icon: Icons.inventory_2_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_missing != null) _missingAlert(),
          _gap([
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _label('Batch scope'),
              AppSelect<String>(
                value: _scope,
                items: [
                  const AppSelectItem(value: _scopeAll, label: 'All batches'),
                  const AppSelectItem(value: _scopeCustom, label: 'Custom selection'),
                  for (final b in _batches)
                    AppSelectItem(
                      value: tStr(b['batchId']),
                      label: tStr(b['batchName']).isNotEmpty
                          ? tStr(b['batchName'])
                          : (tStr(b['batchCode']).isNotEmpty ? tStr(b['batchCode']) : 'Batch ${tStr(b['batchId'])}'),
                    ),
                ],
                onChanged: (v) => _set(() => _scope = v ?? _scopeAll),
              ),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _label('Date', required: true),
              AppDateField(value: businessDateAsDateTime(_date), onChanged: (v) => _set(() => _date = v == null ? '' : isoDay(v))),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _label('Batch name'),
              RawAutocomplete<String>(
                textEditingController: _name,
                focusNode: _nameFocus,
                optionsBuilder: (v) => [for (final n in _priorNames) if (n.toLowerCase().contains(v.text.toLowerCase())) n],
                fieldViewBuilder: (context, c, focus, _) => TextField(controller: c, focusNode: focus, decoration: const InputDecoration(hintText: 'e.g. Morning collection')),
                optionsViewBuilder: (context, onSelected, options) => Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200, maxWidth: 320),
                      child: ListView(padding: EdgeInsets.zero, shrinkWrap: true, children: [
                        for (final o in options) ListTile(dense: true, title: Text(o), onTap: () => onSelected(o)),
                      ]),
                    ),
                  ),
                ),
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
          if (_selectionType == 'CustomBatch')
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0x99F0F9FF), border: Border.all(color: const Color(0xFFBAE6FD)), borderRadius: BorderRadius.circular(6)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text.rich(TextSpan(children: [
                  TextSpan(text: 'Flocks in this batch'),
                  TextSpan(text: ' *', style: TextStyle(color: TColors.red600)),
                ]), style: TextStyle(fontSize: 12, color: TColors.slate600)),
                const SizedBox(height: 8),
                if (_activeFlocks.isEmpty) const Text('No active flocks.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 176),
                  child: SingleChildScrollView(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (final f in _activeFlocks)
                        InkWell(
                          key: ValueKey('bpr-flock-${f['flockId']}'),
                          onTap: () => _toggle(tIntOrNull(f['flockId']) ?? 0, !_selected.contains(tIntOrNull(f['flockId']))),
                          child: Row(children: [
                            Checkbox(
                              value: _selected.contains(tIntOrNull(f['flockId'])),
                              onChanged: (c) => _toggle(tIntOrNull(f['flockId']) ?? 0, c == true),
                            ),
                            Flexible(child: Text(tStr(f['name']), style: const TextStyle(fontSize: 14, color: TColors.slate700))),
                            if (_missingIds.contains(tIntOrNull(f['flockId']))) ...[
                              const SizedBox(width: 6),
                              const TBadge('missing', bg: TColors.amber100, fg: Color(0xFF92400E)),
                            ],
                          ]),
                        ),
                    ]),
                  ),
                ),
              ]),
            ),
          if (_specific && _specificBatch != null) _info("Age from this batch's start date: ${age.weeks}w ${age.days % 7}d (${age.years}y)"),
          if (!_specific) _info('A mixed scope has no single age, so this record saves its age as “Mixed”.'),
        ]),
      ),
      const SizedBox(height: 14),
      ProdSection(
        title: 'Egg Production',
        description: 'Total = crates × 30 + loose eggs. These are BATCH totals, split across flocks at allocation.',
        badge: '${loc(total)} eggs',
        accent: ProdAccent.amber,
        icon: Icons.egg_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, label) in pickRows)
            Container(
              key: ValueKey('bpick-$i'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: TColors.amber200), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.slate700)),
                const SizedBox(height: 6),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(child: ProdNumField(label: 'Crates', value: _crates[i], onChanged: (v) => _set(() => _crates[i] = v))),
                  const SizedBox(width: 8),
                  Expanded(child: ProdNumField(label: 'Loose eggs', value: _loose[i], onChanged: (v) => _set(() => _loose[i] = v))),
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
              ]), style: const TextStyle(fontSize: 14, color: TColors.slate600)),
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Crates equivalent '),
                TextSpan(
                  text: '${crates.crates} crate${crates.crates == 1 ? '' : 's'}${crates.pieces > 0 ? ' + ${crates.pieces} egg${crates.pieces == 1 ? '' : 's'}' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.slate900),
                ),
              ]), style: const TextStyle(fontSize: 14, color: TColors.slate600)),
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
        title: 'Birds',
        description: 'Batch-level deaths and remaining birds. Allocation shares deaths across the included flocks.',
        accent: ProdAccent.emerald,
        icon: Icons.flutter_dash,
        child: _gap([
          _pair(ProdTextField(label: 'Deaths', controller: _deaths), ProdTextField(label: 'Birds left', controller: _birdsLeft)),
          _pair(CalcField(label: 'Flocks in scope', value: '${included.length}'),
              CalcField(label: 'Age', value: _specific ? '${age.weeks}w ${age.days % 7}d' : 'Mixed')),
        ]),
      ),
      const SizedBox(height: 14),
      ProdSection(
        title: 'Feed',
        description: "Drawn from inventory. Allocation computes each flock's share from these lines.",
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
        description: 'Drawn from inventory for the whole batch.',
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
        description: 'Anything worth remembering about this batch.',
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
            item('Deaths', loc(_int(_deaths))),
            item('Flocks in scope', '${included.length}'),
            item('Feed cost', feedCost.toStringAsFixed(2)),
            item('Medication cost', medCost.toStringAsFixed(2)),
            item('Total production cost', round2(feedCost + medCost).toStringAsFixed(2), strong: true),
          ]);
        }),
      ),
      if (!widget.hideActions) ...[
        const Divider(height: 28),
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          if (widget.onCancel != null) OutlinedButton(onPressed: _saving ? null : widget.onCancel, child: const Text('Cancel')),
          OutlinedButton(onPressed: _saving ? null : () => save('Draft'), child: Text(_saving ? 'Saving…' : 'Save as Draft')),
          FilledButton(
            onPressed: _saving ? null : () => save('PendingAllocation'),
            child: Text(_edit ? 'Save Batch Production' : 'Log Batch Production'),
          ),
        ]),
      ],
    ]);
  }

  void _toggle(int flockId, bool checked) => _set(() {
        _selected = checked ? {..._selected, flockId}.toList() : [for (final id in _selected) if (id != flockId) id];
      });
}

// ------------------------------------------------------------ the modal

/// BatchProductionRecordModal: header (title, scope • flocks • date, Open
/// Full Page, close), the form, and a footer with the running figures and
/// Cancel / Save as Draft / Log Batch Production.
Future<bool?> showBatchProductionRecordModal(BuildContext context, {required Session session, required Company company, int? recordId}) =>
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BatchModal(session: session, company: company, recordId: recordId),
    );

class _BatchModal extends StatefulWidget {
  const _BatchModal({required this.session, required this.company, this.recordId});
  final Session session;
  final Company company;
  final int? recordId;
  @override
  State<_BatchModal> createState() => _BatchModalState();
}

class _BatchModalState extends State<_BatchModal> {
  final _form = GlobalKey<BatchProductionRecordFormState>();
  BatchFormStatus? _s;
  Duration _offset = DateTime.now().timeZoneOffset;
  bool get _edit => widget.recordId != null;
  String get _fullHref => _edit ? '/batch-production-records/${widget.recordId}/edit' : '/batch-production-records/new';

  @override
  void initState() {
    super.initState();
    _loadClock();
  }

  Future<void> _loadClock() async {
    final c = await CompanyClock.load(widget.session, widget.company);
    if (mounted) setState(() => _offset = c.offset);
  }

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
    if ((_s?.dirty ?? false) && !await _confirmDiscard(false)) return;
    if (mounted) Navigator.pop(context, false);
  }

  Future<void> _fullPage() async {
    if ((_s?.dirty ?? false) && !await _confirmDiscard(true)) return;
    if (!mounted) return;
    final nav = Navigator.of(context);
    nav.pop(false);
    openAppHref(nav.context, widget.session, widget.company, _fullHref, label: 'Batch production record');
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final contextLine = [
      if (s?.scopeLabel != null && s!.scopeLabel!.isNotEmpty) s.scopeLabel!,
      if (s != null) '${s.includedFlockCount} flock${s.includedFlockCount == 1 ? '' : 's'}',
      if (s != null && s.date.isNotEmpty) fmtDateTime(s.date, null, _offset),
    ].join(' • ');
    final saving = s?.saving ?? false, loading = s?.loading ?? false;
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
            backgroundColor: const Color(0xFFE0F2FE),
            titleSpacing: 12,
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_edit ? 'Edit Batch Production Record' : 'Add Batch Production Record',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: TColors.slate900)),
              Text(
                contextLine.isNotEmpty ? contextLine : (_edit ? 'Update batch-level production totals' : 'Log total production for a batch or group of flocks'),
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
            BatchProductionRecordForm(
              key: _form,
              session: widget.session,
              company: widget.company,
              recordId: widget.recordId,
              hideActions: true,
              onStatus: (v) {
                if (mounted) setState(() => _s = v);
              },
              onSaved: (_, _) => Navigator.pop(context, true),
            ),
          ]),
          bottomNavigationBar: SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: TColors.slate200))),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (s != null && !loading)
                  Wrap(spacing: 14, runSpacing: 2, children: [
                    stat('Total eggs', loc(s.totalEggs)),
                    stat('Crates', '${s.crates} + ${s.pieces}'),
                    stat('Net sellable', loc(s.netSellable), color: TColors.emerald700),
                    stat('Deaths', loc(s.deaths), color: s.deaths > 0 ? TColors.rose700 : null),
                    stat('Feed cost', s.feedCost.toStringAsFixed(2)),
                  ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: saving ? null : _close, child: const Text('Cancel'))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: saving || loading ? null : () => _form.currentState?.save('Draft'),
                      child: const Text('Save as Draft'),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: saving || loading ? null : () => _form.currentState?.save('PendingAllocation'),
                  child: Text(_edit ? 'Save Batch Production' : 'Log Batch Production'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ full pages

/// app/batch-production-records/new (with the missing-production prefill)
/// and app/batch-production-records/[id]/edit.
class BatchProductionRecordPage extends StatelessWidget {
  const BatchProductionRecordPage({super.key, required this.session, required this.company, this.recordId, this.prefill, this.invalidId = false});
  final Session session;
  final Company company;
  final int? recordId;
  final MissingProductionPrefill? prefill;

  /// `[id]/edit` with an id that is not a positive number.
  final bool invalidId;

  @override
  Widget build(BuildContext context) {
    final edit = recordId != null || invalidId;
    void back() => Navigator.of(context).maybePop();
    void go(String href) {
      final nav = Navigator.of(context);
      nav.pop();
      openAppHref(nav.context, session, company, href, label: 'Batch Production');
    }

    return Scaffold(
      appBar: AppBar(title: Text(edit ? 'Edit Batch Production Record' : 'Add New Batch Production Record')),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.inventory_2_outlined, size: 20, color: Color(0xFF0284C7)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(edit ? 'Edit Batch Production Record' : 'Add New Batch Production Record',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
              Text(edit ? 'Update total production for a batch or group of flocks' : 'Log total production for a batch or group of flocks',
                  style: const TextStyle(fontSize: 13, color: TColors.slate600)),
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
        if (invalidId)
          const Text('That batch production record could not be found.', style: TextStyle(fontSize: 14, color: TColors.slate500))
        else
          BatchProductionRecordForm(
            session: session,
            company: company,
            recordId: recordId,
            prefill: recordId == null ? prefill : null,
            onSaved: (status, id) {
              final p = prefill;
              if (recordId == null && p != null) {
                final backHref = farmCompletenessHref(p.date);
                go(status == 'PendingAllocation' && id != null
                    ? '/batch-production-records/$id/allocate?returnTo=${Uri.encodeComponent(backHref)}'
                    : backHref);
                return;
              }
              back();
            },
            onCancel: back,
          ),
      ]),
    );
  }
}
