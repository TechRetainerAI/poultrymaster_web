import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/form_section.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../list_screen.dart';
import '../lookup_loader.dart';
import '../registry.dart';
import '../shared/business_dates.dart' show fmtNum, isoDay;
import '../shared/company_clock.dart';
import 'bird_reconciliation.dart';
import 'breed_picker.dart';
import 'flock_history.dart';
import 'flock_type.dart';
import 'poultry_features.dart';

import 'package:poultrycore_mobile/design/tone.dart';

/// Flock Groups → Add / Edit flock, as the web's dialogs in
/// `app/flocks/page.tsx`.
///
/// Its own screen because the dialog is not a flat form: picking a batch
/// prefills the start date and breed and shows how many birds it has left,
/// "Active Flock" only applies once the flock has arrived, the inactivation
/// reason appears only for an inactive flock, and "Other" asks for the reason.
/// The batch and house dropdowns read `/MainFlockBatch` and `/House`, which
/// the generic form could not trace.
class FlockFormScreen extends StatefulWidget {
  const FlockFormScreen({
    super.key,
    required this.session,
    required this.company,
    this.existing,
  });

  final Session session;
  final Company company;
  final Map<String, dynamic>? existing;

  @override
  State<FlockFormScreen> createState() => _FlockFormScreenState();
}

const _inactivationReasons = <(String, String)>[
  ('all flock sold', 'All flock sold'),
  ('all flocks on the market', 'All flocks on the market'),
  ('disease outbreak', 'Disease outbreak'),
  ('end of production cycle', 'End of production cycle'),
  ('relocation', 'Relocation'),
  ('other', 'Other'),
];

/// The dropdown value for "Create a flock batch"; never a real batch id.
const _createBatch = '__create_batch__';

class _Batch {
  const _Batch(this.id, this.name, this.birds, this.startDate, this.breed);
  final int id;
  final String name;
  final int birds;
  final String? startDate;
  final String? breed;
}

class _House {
  const _House(this.id, this.name, this.capacity);
  final int id;
  final String name;
  final int capacity;
}

class _FlockFormScreenState extends State<FlockFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _quantity = TextEditingController();
  final _otherReason = TextEditingController();
  final _notes = TextEditingController();

  int? _batchId;
  int? _houseId;
  DateTime? _startDate;
  String _breed = '';
  bool _active = true;
  bool _hasArrived = false;
  String _inactivationReason = '';

  /// '' = automatic: the server's default (broiler breed, else company type).
  /// An existing flock always carries its stored type.
  String _flockType = '';
  String? _businessType;

  List<_Batch>? _batches;
  List<_House>? _houses;
  List<Map<String, dynamic>> _houseRows = const [];
  List<Map<String, dynamic>> _flocks = const [];

  /// 413: the server's bird accounting per batch; empty before 413.
  Map<int, Map> _recon = const {};

  /// Saved opening positions: the birds ORIGINALLY placed, keyed by flock.
  Map<int, Map> _openingByFlock = const {};

  /// 413: a new flock, or one already operating.
  bool _existingMode = false;
  final _existingDraft = ExistingFlockDraft(isoDay(DateTime.now()));

  /// 414: the flock as it was registered, from posted records.
  Map? _editCtx;
  OpeningHistoryDraft? _openingDraft;
  Duration _offset = DateTime.now().timeZoneOffset;
  String? _loadError;

  bool _saving = false;
  String? _error;

  Map<String, dynamic>? get _row => widget.existing;
  bool get _editing => _row != null;
  int? get _flockId => int.tryParse('${_row?['flockId'] ?? ''}');

  _Batch? get _selectedBatch =>
      _batches?.where((b) => b.id == _batchId).firstOrNull;

  int get _qty => int.tryParse(_quantity.text.trim()) ?? 0;

  @override
  void initState() {
    super.initState();
    final r = _row;
    if (r != null) {
      _name.text = '${r['name'] ?? ''}';
      _quantity.text = '${r['quantity'] ?? ''}';
      _breed = '${r['breed'] ?? ''}';
      _startDate = DateTime.tryParse('${r['startDate'] ?? ''}');
      _active = r['active'] == true;
      _hasArrived = r['hasArrived'] == true;
      _batchId = int.tryParse('${r['batchId'] ?? ''}');
      if (_batchId == 0) _batchId = null;
      _houseId = int.tryParse('${r['houseId'] ?? ''}');
      _inactivationReason = '${r['inactivationReason'] ?? ''}';
      _otherReason.text = '${r['otherReason'] ?? ''}';
      _notes.text = '${r['notes'] ?? ''}';
      _flockType = flockTypeOf(r);
    }
    _quantity.addListener(() => setState(() {}));
    _name.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _quantity, _otherReason, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _scope => {
        'farmId': widget.company.farmId,
        'userId': widget.session.tokens.userId ?? '',
      };

  Future<List<Map<String, dynamic>>> _list(String path) async {
    final res = await widget.session.farmClient.get(path, query: _scope);
    return [
      for (final r in LookupLoader.rowsIn(res))
        if (r is Map) Map<String, dynamic>.from(r),
    ];
  }

  static int _int(Object? v) => int.tryParse('${v ?? ''}') ?? 0;

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _list('/api/MainFlockBatch'),
        _list('/api/House'),
        _list('/api/Flock'),
      ]);
      final businessType = await loadPoultryBusinessType(widget.session, widget.company);
      final recon = await loadBatchReconciliation(widget.session, widget.company);
      final opening = await _loadOpening();
      final ctx = _editing && _flockId != null ? await loadFlockEditContext(widget.session, widget.company, _flockId!) : null;
      final clock = await CompanyClock.load(widget.session, widget.company);
      if (!mounted) return;
      setState(() {
        _recon = recon;
        _openingByFlock = opening;
        _offset = clock.offset;
        if (_editing) {
          _editCtx = ctx;
          _openingDraft = openingDraftFrom(ctx);
        }
        _houseRows = results[1];
        _batches = [
          for (final b in results[0])
            if (_int(b['batchId']) > 0)
              _Batch(
                _int(b['batchId']),
                '${b['batchName'] ?? 'Batch ${b['batchId']}'}',
                _int(b['numberOfBirds']),
                b['startDate']?.toString(),
                b['breed']?.toString(),
              ),
        ];
        _houses = [
          for (final h in results[1])
            if (_int(h['houseId']) > 0)
              _House(
                _int(h['houseId']),
                '${h['houseName'] ?? h['name'] ?? 'House ${h['houseId']}'}',
                _int(h['capacity']),
              ),
        ];
        _flocks = results[2];
        _businessType = businessType;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (_) {
      if (mounted) setState(() => _loadError = 'Could not load batches and houses.');
    }
  }

  /// Latest opening position per flock (same rule as the edit context).
  Future<Map<int, Map>> _loadOpening() async {
    try {
      final r = await widget.session.farmClient.get('/api/PoultryFarmSetup/opening-positions', query: _scope);
      final p = r is Map ? (r['positions'] ?? (r['data'] is Map ? r['data']['positions'] : null)) : null;
      final out = <int, Map>{};
      for (final x in p is List ? p : const []) {
        if (x is! Map) continue;
        final prev = out[_int(x['flockId'])];
        if (prev == null || _int(x['openingPositionId']) > _int(prev['openingPositionId'])) out[_int(x['flockId'])] = x;
      }
      return out;
    } catch (_) {
      return const {}; // the form still works on flock quantities
    }
  }

  /// Birds a flock was placed with: its opening position, else its quantity.
  int _placedBirds(Map f) {
    final o = _openingByFlock[_int(f['flockId'])];
    return o != null && o['originallyPlaced'] != null ? _int(o['originallyPlaced']) : _int(f['quantity']);
  }

  /// Birds of a batch not in any flock yet.
  int _notYetPlaced(_Batch b) {
    final r = _recon[b.id];
    if (r != null) return _int(r['unallocatedPool']).clamp(0, 1 << 31);
    final used = _flocks.where((f) => _int(f['batchId']) == b.id).fold<int>(0, (a, f) => a + _placedBirds(f));
    return (b.birds - used).clamp(0, 1 << 31);
  }

  /// The birds on the form: Edit Flock with an opening history takes them
  /// from the history (live at registration + adjustments since).
  int get _birdsOnForm => _openingDraft != null
      ? (int.tryParse(_openingDraft!.live.trim()) ?? 0) + _int(_editCtx?['quantityAdjustments'])
      : _qty;

  /// The batch dropdown's last option: go to Flock Purchases (Batches) to
  /// add one, then come back with it already picked. Without this a farm
  /// with no batch was stuck on a dead dropdown and had to find that page.
  Future<void> _goCreateBatch() async {
    final spec = PageRegistry.of('flock');
    if (spec == null) return;
    final before = {for (final b in _batches ?? const <_Batch>[]) b.id};
    // Opening a route from inside the dropdown's own callback can race the
    // menu closing; let this frame finish first.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ListScreen(spec: spec, session: widget.session, company: widget.company),
    ));
    if (!mounted) return;
    await _load();
    final added = (_batches ?? const <_Batch>[]).where((b) => !before.contains(b.id)).toList();
    if (added.isNotEmpty) {
      _pickBatch(added.last.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Batch "${added.last.name}" selected.')));
      }
    }
  }

  /// handleCreateBatchChange: prefill start date and breed from the batch.
  void _pickBatch(int? id) {
    setState(() {
      _batchId = id;
      final b = _selectedBatch;
      if (b == null || _editing) return;
      final d = DateTime.tryParse(b.startDate ?? '');
      if (d != null) _startDate = d;
      if ((b.breed ?? '').isNotEmpty) {
        _breed = b.breed!;
      }
    });
  }

  /// Breeds already used on this farm come first, as on the web.
  List<String> get _knownBreeds {
    final seen = <String>{};
    final out = <String>[];
    void add(String raw) {
      final v = raw.trim();
      if (v.isEmpty || !seen.add(v.toLowerCase())) return;
      out.add(v);
    }

    add(_breed);
    final farm = [for (final f in _flocks) '${f['breed'] ?? ''}']..sort();
    farm.forEach(add);
    return out;
  }


  void _fail(String msg) {
    setState(() => _error = msg);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (_name.text.trim().isEmpty || _startDate == null) {
      return _fail('Add a flock name and the date the flock started.');
    }
    // A flock registered with an opening position takes its count from the
    // history section; any other flock needs a count on the form.
    if (_openingDraft == null && _qty <= 0) {
      return _fail(!_editing && _existingMode
          ? 'Enter how many birds were originally placed in this flock.'
          : 'Enter how many birds are in this flock — use a number greater than zero.');
    }
    final existing = !_editing && _existingMode ? existingFlockHistory(_qty, _existingDraft) : null;
    if (existing?.problem != null) return _fail(existing!.problem!);
    if (!_editing && _batchId == null) {
      return _fail('Link this flock to a batch so bird counts stay accurate.');
    }
    final batch = _selectedBatch;
    if (!_editing && batch != null && _qty > batch.birds) {
      return _fail('That batch only has ${batch.birds} birds available — '
          'lower the flock size or pick another batch.');
    }
    // Room capacity. A new flock cannot overfill the house; on Edit,
    // out-of-proportion numbers are warnings and the save still goes through.
    final localWarnings = <String>[if (_editing) ...openingDraftWarnings(_editCtx, _openingDraft)];
    final house = _houses?.where((h) => h.id == _houseId).firstOrNull;
    if (house != null && house.capacity > 0) {
      final occupied = _flocks
          .where((f) =>
              _int(f['houseId']) == house.id &&
              f['active'] == true &&
              _int(f['flockId']) != (_flockId ?? -1))
          .fold<int>(0, (s, f) => s + _int(f['quantity']));
      if (_editing) {
        if (occupied + _birdsOnForm > house.capacity) {
          localWarnings.add('${house.name} holds ${fmtNum(house.capacity, 0)} birds'
              '${occupied > 0 ? ' and already has ${fmtNum(occupied, 0)}' : ''}; '
              'with this flock it has ${fmtNum(occupied + _birdsOnForm, 0)}.');
        }
      } else {
        // An existing flock occupies the pen with the birds standing today.
        final standing = existing != null ? existing.history['currentLiveBirds'] as int : _qty;
        if (occupied + standing > house.capacity) {
          return _fail('${house.name} holds ${house.capacity} birds'
              '${occupied > 0 ? ' and already has $occupied' : ''}. '
              "You're trying to place ${fmtNum(occupied + standing, 0)}. "
              'Reduce the number or pick another room.');
        }
      }
    }

    setState(() => _saving = true);
    final d = _startDate!;
    final day = isoDay(d);
    final body = <String, dynamic>{
      ..._scope,
      if (_editing) 'flockId': _flockId,
      'name': _name.text.trim(),
      'startDate': day,
      'breed': _breed.trim(),
      'quantity': _editing ? _birdsOnForm : _qty,
      'active': _active,
      'hasArrived': _hasArrived,
      'houseId': _houseId,
      'batchId': _batchId ?? 0,
      'inactivationReason': _inactivationReason,
      'otherReason': _inactivationReason == 'other' ? _otherReason.text.trim() : '',
      'notes': _notes.text.trim(),
      // 399: omitted -> a new flock takes the database default (broiler
      // breed, else company type), and an existing one keeps its type.
      if (_flockType.isNotEmpty) 'flockType': _flockType,
      // 414: the opening history is saved with the flock; the server posts
      // only the difference.
      if (_editing && _openingDraft != null) 'OpeningHistory': _openingDraft!.toEdit(),
    };
    try {
      final client = widget.session.farmClient;
      var message = _editing ? 'Flock updated successfully.' : 'Flock created successfully.';
      if (_editing) {
        final res = await client.put('/api/Flock/$_flockId', body: body);
        // Server warnings restate the local ones more precisely; show each once.
        final raw = res is Map ? (res['warnings'] ?? res['Warnings'] ?? (res['data'] is Map ? res['data']['warnings'] : null)) : null;
        final warnings = <String>{
          for (final w in raw is List ? raw : const []) if (w is String && w.isNotEmpty) w,
          ...localWarnings,
        };
        if (warnings.isNotEmpty) message = 'Flock updated — please check — ${warnings.join(' ')}';
      } else if (existing != null) {
        // One transaction on the server: the flock at its remaining birds, the
        // batch charged the placed birds once, the difference as opening history.
        await client.post('/api/Flock/existing', body: {
          'flock': {...body, 'startDate': '${day}T00:00:00'},
          'history': existing.history,
          'asOfDate': _existingDraft.asOfDate,
          'source': 'Flocks page',
        });
        message = 'Flock created: ${fmtNum(existing.history['originallyPlaced'] as int, 0)} placed, '
            '${fmtNum(existing.history['currentLiveBirds'] as int, 0)} remaining.';
      } else {
        await client.post('/api/Flock', body: body);
      }
      // A new or retyped flock can change which egg / broiler pages show.
      loadPoultryFeatures(widget.session, widget.company, force: true);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save: $e';
      });
    }
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final batch = _selectedBatch;
    final loading = _batches == null && _loadError == null;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_editing ? 'Edit Flock' : 'Add New Flock',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(
              _editing ? 'Update the flock information below' : 'Enter the flock information below',
              style: TextStyle(fontSize: 11.5, color: tokens.mutedForeground),
            ),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            if (loading) const LinearProgressIndicator(),
            for (final msg in [_loadError, _error])
              if (msg != null) ...[
                _ErrorBox(message: msg),
                const SizedBox(height: 12),
              ],
            if (!_editing) ...[
              FlockModeSelector(
                existing: _existingMode,
                onChanged: _saving ? null : (v) => setState(() => _existingMode = v),
              ),
              const SizedBox(height: 12),
            ],
            FormSection(title: 'Flock Information', color: SectionColor.indigo, children: [
              AppField(
                label: 'Assign to Flock Batch',
                required: !_editing,
                full: true,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  AppSelect<String>(
                    value: _batchId?.toString(),
                    enabled: !loading,
                    hintText: loading
                        ? 'Loading…'
                        : (_batches?.isEmpty ?? true)
                            ? 'No batches yet — tap to create one'
                            : 'Please select a batch',
                    items: [
                      for (final b in _batches ?? const <_Batch>[])
                        AppSelectItem(value: '${b.id}', label: b.name),
                      const AppSelectItem(value: _createBatch, label: '＋ Create a flock batch'),
                    ],
                    onChanged: (v) => v == _createBatch
                        ? _goCreateBatch()
                        : _pickBatch(int.tryParse(v ?? '')),
                  ),
                  if (batch != null) ...[
                    const SizedBox(height: 6),
                    BatchAvailability(
                      size: batch.birds,
                      free: _notYetPlaced(batch),
                      recon: _recon[batch.id],
                      // Editing gives the flock back its own birds: they count
                      // against its batch today and would be freed by the change.
                      ownBirds: _editing && _row != null && _int(_row!['batchId']) == batch.id ? _placedBirds(_row!) : 0,
                    ),
                  ],
                ]),
              ),
              AppField(
                label: 'Name',
                required: true,
                child: AppInput(
                  controller: _name,
                  hintText: 'e.g., Flock A - Rhode Island Reds',
                  validator: _req,
                ),
              ),
              AppField(
                label: 'Breed',
                child: BreedPicker(
                  value: _breed,
                  known: _knownBreeds,
                  onChanged: (v) => setState(() => _breed = v),
                ),
              ),
              AppField(
                label: 'Flock type',
                child: FlockTypeSelect(
                  value: _flockType.isNotEmpty ? _flockType : defaultFlockType(_breed, _businessType),
                  automatic: _flockType.isEmpty,
                  enabled: !_saving,
                  onChanged: (t) => setState(() => _flockType = t),
                ),
              ),
              AppField(
                label: 'Start Date',
                required: true,
                child: AppDateField(
                  value: _startDate,
                  onChanged: (d) => setState(() => _startDate = d),
                ),
              ),
              AppField(
                label: !_editing && _existingMode ? 'Birds Originally Placed' : 'Number of Birds',
                required: true,
                full: true,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  if (_editing && _openingDraft != null) ...[
                    AppNumberInput(
                      key: const ValueKey('flock-quantity-locked'),
                      controller: TextEditingController(text: '$_birdsOnForm'),
                      enabled: false,
                    ),
                    const SizedBox(height: 4),
                    _hint('Set from the registered bird count in Bird history below.'),
                  ] else ...[
                    AppNumberInput(
                      controller: _quantity,
                      hintText: 'e.g., 100',
                      validator: _req,
                    ),
                    if (_editing && _int((_editCtx?['position'] as Map?)?['productionrecordcount']) > 0) ...[
                      const SizedBox(height: 4),
                      _hint('Birds placed. Live birds now (${fmtNum(_int((_editCtx?['position'] as Map?)?['currentlivebirds']), 0)}) '
                          'come from the latest production record.'),
                    ],
                    if (!_editing && batch != null && _qty > 0) ...[
                      const SizedBox(height: 4),
                      if (_notYetPlaced(batch) - _qty >= 0)
                        _hint('${fmtNum(_notYetPlaced(batch) - _qty, 0)} birds left to place after this')
                      else
                        _hint('${fmtNum(_qty - _notYetPlaced(batch), 0)} more than the batch has left to place', red: true),
                    ],
                  ],
                ]),
              ),
              if (!_editing && _existingMode)
                AppField(
                  label: '',
                  full: true,
                  child: ExistingFlockFields(
                    placed: _qty,
                    draft: _existingDraft,
                    enabled: !_saving,
                    onChanged: () => setState(() {}),
                  ),
                ),
              AppField(
                label: 'Assign to House',
                full: true,
                child: HousePicker(
                  houses: _houseRows,
                  flocks: _flocks,
                  value: _houseId,
                  enabled: !loading,
                  excludeFlockId: _flockId,
                  birds: !_editing && _existingMode ? (int.tryParse(_existingDraft.currentLiveBirds.trim()) ?? 0) : _birdsOnForm,
                  onChanged: (id) => setState(() => _houseId = id),
                ),
              ),
            ]),
            if (_editing && _editCtx != null) ...[
              const SizedBox(height: 12),
              FlockHistoryPanel(
                ctx: _editCtx!,
                draft: _openingDraft,
                onChanged: () => setState(() {}),
                enabled: !_saving,
                offset: _offset,
              ),
            ],
            const SizedBox(height: 12),
            FormSection(title: 'Status & Notes', color: SectionColor.green, columns: 1, children: [
              AppField(
                label: '',
                full: true,
                child: AppSwitchRow(
                  label: 'Flock Has Arrived',
                  description: '(Leave off until birds physically arrive — status stays Pending)',
                  value: _hasArrived,
                  onChanged: (v) => setState(() => _hasArrived = v),
                ),
              ),
              AppField(
                label: '',
                full: true,
                child: AppSwitchRow(
                  label: 'Active Flock',
                  description: '(Only applies once the flock has arrived)',
                  value: _active,
                  onChanged: _hasArrived ? (v) => setState(() => _active = v) : null,
                ),
              ),
              if (!_active) ...[
                AppField(
                  label: 'Inactivation Reason',
                  full: true,
                  child: AppSelect<String>(
                    value: _inactivationReasons.any((r) => r.$1 == _inactivationReason)
                        ? _inactivationReason
                        : null,
                    hintText: 'Select a reason',
                    items: [
                      for (final (v, l) in _inactivationReasons) AppSelectItem(value: v, label: l),
                    ],
                    onChanged: (v) => setState(() => _inactivationReason = v ?? ''),
                  ),
                ),
                if (_inactivationReason == 'other')
                  AppField(
                    label: 'Other Reason',
                    full: true,
                    child: AppInput(
                      controller: _otherReason,
                      hintText: 'Please specify the reason',
                    ),
                  ),
              ],
              AppField(
                label: 'Notes (Optional)',
                full: true,
                child: AppTextarea(
                  controller: _notes,
                  hintText: 'Add any additional notes about the flock',
                ),
              ),
            ]),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.destructive,
                    size: AppButtonSize.lg,
                    fullWidth: true,
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: _editing ? 'Update Flock' : 'Create Flock',
                    size: AppButtonSize.lg,
                    fullWidth: true,
                    busy: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error.withValues(alpha: .08),
        border: Border.all(color: error.withValues(alpha: .4)),
        borderRadius: BorderRadius.circular(Dim.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: error),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(color: error, fontSize: 13))),
        ],
      ),
    );
  }
}

Widget _hint(String text, {bool red = false}) =>
    Text(text, style: TextStyle(fontSize: 12, color: red ? const Tone.fg(0xFFDC2626) : const Tone.fg(0xFF64748B)));
