import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/inputs.dart';
import '../../design/web_mobile.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../lookup_loader.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';
import '../web_nav.dart';
import 'breed_picker.dart';
import 'farm_setup_dialogs.dart';
import 'farm_setup_wizard.dart';

/// Poultry → Tools → Initial Farm Setup, as `app/poultry-farm-setup/page.tsx`
/// with the rules of `lib/farm-setup/wizard.ts` (farm_setup_wizard.dart).
///
/// Onboarding for a poultry farm that already has birds: Houses/Pens →
/// Batches → Allocate Batches / Create Flocks → Opening Reconciliation →
/// Review, then one POST that creates everything. Historical losses become an
/// OPENING POSITION, never a production record.
///
/// The unfinished setup is kept on the SERVER per company (migration 328), in
/// the web's JSON shape, so it can be resumed here or on the web.
class InitialFarmSetupScreen extends StatefulWidget {
  const InitialFarmSetupScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<InitialFarmSetupScreen> createState() => _InitialFarmSetupScreenState();
}

const setupSteps = ['Houses/Pens', 'Batches', 'Allocate Batches / Create Flocks', 'Opening Reconciliation', 'Review'];

// Tailwind tones the page uses.
const _slate50 = Color(0xFFF8FAFC);
const _slate100 = Color(0xFFF1F5F9);
const _slate200 = Color(0xFFE2E8F0);
const _slate300 = Color(0xFFCBD5E1);
const _slate400 = Color(0xFF94A3B8);
const _slate500 = Color(0xFF64748B);
const _slate600 = Color(0xFF475569);
const _slate700 = Color(0xFF334155);
const _slate900 = Color(0xFF0F172A);
const _blue50 = Color(0xFFEFF6FF);
const _blue100 = Color(0xFFDBEAFE);
const _blue200 = Color(0xFFBFDBFE);
const _blue300 = Color(0xFF93C5FD);
const _blue400 = Color(0xFF60A5FA);
const _blue600 = Color(0xFF2563EB);
const _blue700 = Color(0xFF1D4ED8);
const _blue900 = Color(0xFF1E3A8A);
const _indigo600 = Color(0xFF4F46E5);
const _emerald50 = Color(0xFFECFDF5);
const _emerald200 = Color(0xFFA7F3D0);
const _emerald600 = Color(0xFF059669);
const _emerald700 = Color(0xFF047857);
const _emerald800 = Color(0xFF065F46);
const _emerald900 = Color(0xFF064E3B);
const _amber50 = Color(0xFFFFFBEB);
const _amber200 = Color(0xFFFDE68A);
const _amber300 = Color(0xFFFCD34D);
const _amber600 = Color(0xFFD97706);
const _amber700 = Color(0xFFB45309);
const _amber800 = Color(0xFF92400E);
const _amber900 = Color(0xFF78350F);
const _red50 = Color(0xFFFEF2F2);
const _red200 = Color(0xFFFECACA);
const _red300 = Color(0xFFFCA5A5);
const _red500 = Color(0xFFEF4444);
const _red600 = Color(0xFFDC2626);
const _red700 = Color(0xFFB91C1C);
const _purple700 = Color(0xFF7E22CE);

/// The TONES of /production-records' stat tiles: only the number is coloured.
const _tones = {
  'slate': _slate900,
  'blue': _blue700,
  'emerald': _emerald600,
  'amber': _amber600,
  'violet': _purple700,
  'rose': _red600,
};

class _InitialFarmSetupScreenState extends State<InitialFarmSetupScreen> {
  bool _loading = true;
  SetupContext _ctx = SetupContext(businessDate: isoDay(DateTime.now()));
  Map<String, dynamic>? _status;
  Map<String, dynamic>? _opening;

  /// choose | wizard | newBatch | done | completed
  String _screen = 'choose';
  int _step = 0;
  bool _saving = false;
  bool _submitted = false;
  Map<String, dynamic>? _result;
  Map<String, Map<int, Map<String, String>>> _serverErrors = {};
  SetupDraft _draft = SetupDraft();

  Map<String, dynamic>? _savedDraft;

  /// idle | saving | saved | error
  String _draftState = 'idle';
  Timer? _saveTimer;
  Duration _offset = Duration.zero;

  // Batch generator.
  String _batchCount = '2';
  String _batchPrefix = 'Batch';
  String _batchCodePrefix = 'B';
  String? _batchStartOverride;
  String _batchBreed = '';
  String _batchBirds = '';
  String _batchDate = '';

  // House generator.
  String _penCount = '6';
  String _penPrefix = 'Pen';
  String? _penStartOverride;
  String _penCapacity = '';
  String _penLocation = '';

  /// all | empty | new
  String _houseFilter = 'all';
  String _selectedBatchKey = '';

  /// batch | pens | allocate
  String _allocPhase = 'batch';
  bool _showAllBatches = false;
  bool _showExistingFlocks = false;
  bool _showExistingBatches = false;
  List<Map<String, dynamic>> _suppliers = const [];
  List<Map<String, dynamic>> _cashAccounts = const [];
  final Set<String> _openReviewBatches = {};

  final Map<String, TextEditingController> _ctls = {};

  ApiClient get _client => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  String get _userId => widget.session.tokens.userId ?? '';
  Map<String, String> get _scope => {'userId': _userId, 'farmId': _farmId};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    for (final c in _ctls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------ loading

  Future<Object?> _get(String path) async {
    try {
      return await _client.get(path, query: _scope);
    } on ApiException {
      return null;
    }
  }

  Future<void> _load({bool keepScreen = false}) async {
    if (_userId.isEmpty || _farmId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = !keepScreen);
    ApiException? ctxError;
    Object? ctxRes;
    try {
      ctxRes = await _client.get('/api/PoultryFarmSetup/context', query: _scope);
    } on ApiException catch (e) {
      ctxError = e;
    }
    final rest = await Future.wait([
      _get('/api/PoultryFarmSetup/opening-positions'),
      _get('/api/Supplier'),
      _get('/api/PoultryFarmSetup/draft'),
      _get('/api/Poultry/cash-accounts'),
      CompanyClock.load(widget.session, widget.company),
    ]);
    if (!mounted) return;
    final draftRes = rest[2];
    setState(() {
      _offset = (rest[4] as CompanyClock).offset;
      _suppliers = [for (final s in LookupLoader.rowsIn(rest[1])) if (s is Map) Map<String, dynamic>.from(s)];
      _cashAccounts = [
        for (final a in LookupLoader.rowsIn(rest[3]))
          if (a is Map && a['isActive'] != false) Map<String, dynamic>.from(a),
      ];
      if (rest[0] is Map) _opening = Map<String, dynamic>.from(rest[0] as Map);
      if (ctxRes is Map) {
        _ctx = SetupContext.fromServer(ctxRes, isoDay(DateTime.now()));
        _status = ctxRes['status'] is Map ? Map<String, dynamic>.from(ctxRes['status'] as Map) : null;
        _savedDraft = draftRes is Map && draftRes['hasDraft'] == true && draftRes['draft'] is Map
            ? Map<String, dynamic>.from(draftRes['draft'] as Map)
            : null;
        // Arriving fresh gets an explicit offer to resume, never a silent
        // restore into a half-finished form.
        if (!keepScreen) _go(_status?['isComplete'] == true ? 'completed' : 'choose');
      }
      _loading = false;
    });
    if (ctxRes is! Map) {
      _toast('Could not load farm setup', ctxError?.message ?? 'Please try again.');
    }
  }

  void _toast(String title, [String? detail]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(detail == null || detail.isEmpty ? title : '$title. $detail')));
  }

  /// Move the wizard (the web moves the address bar with it).
  void _go(String screen, [int step = 0]) {
    _screen = screen;
    _step = step;
  }

  // -------------------------------------------------------- draft saving

  /// Every edit: apply, redraw, and save the draft after 1.2 s of quiet.
  void _edit(VoidCallback fn) {
    setState(fn);
    _scheduleSave();
  }

  void _scheduleSave() {
    if (_screen != 'wizard' || _userId.isEmpty) return;
    setState(() => _draftState = 'saving');
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1200), _saveDraftNow);
  }

  Future<void> _saveDraftNow() async {
    try {
      await _client.put('/api/PoultryFarmSetup/draft', body: {
        'FarmId': _farmId,
        'Draft': jsonEncode(_draft.toJson()),
        'Step': _step,
        'Phase': _allocPhase,
        'UpdatedBy': _userId,
      });
      if (mounted) setState(() => _draftState = 'saved');
    } on ApiException {
      if (mounted) setState(() => _draftState = 'error');
    }
  }

  Future<void> _clearSavedDraft() async {
    _saveTimer?.cancel();
    try {
      await _client.delete(
          '/api/PoultryFarmSetup/draft?userId=${Uri.encodeQueryComponent(_userId)}&farmId=${Uri.encodeQueryComponent(_farmId)}');
    } on ApiException {
      // The web ignores a failed discard too.
    }
    if (mounted) {
      setState(() {
        _savedDraft = null;
        _draftState = 'idle';
      });
    }
  }

  // --------------------------------------------------------- derivations

  ({List<SetupRowError> errors, List<SetupRowError> warnings}) get _validation => validateSetup(_draft, _ctx);

  List<String> get _knownBreeds {
    final seen = <String>{};
    return [
      for (final b in [..._ctx.existingBatches.map((b) => b.breed), ..._draft.batches.map((b) => b.breed)])
        if (b.trim().isNotEmpty && seen.add(b.trim())) b.trim(),
    ];
  }

  String? _errorFor(Map<String, Map<int, Map<String, String>>> fieldErrors, String section, int index, String field) {
    final live = fieldErrors[section]?[index]?[field];
    if (live != null && _submitted) return live;
    return _serverErrors[section]?[index]?[field] ?? (live != null && _step == 4 ? live : null);
  }

  bool _rowInvalid(Map<String, Map<int, Map<String, String>>> fieldErrors, String section, int index) =>
      (_submitted && (fieldErrors[section]?[index]?.isNotEmpty ?? false)) ||
      (_serverErrors[section]?[index]?.isNotEmpty ?? false);

  TextEditingController _ctl(String id, String value) {
    final c = _ctls.putIfAbsent(id, () => TextEditingController(text: value));
    if (c.text != value) {
      c.value = TextEditingValue(text: value, selection: TextSelection.collapsed(offset: value.length));
    }
    return c;
  }

  // ------------------------------------------------------------ actions

  void _resumeDraft() {
    final saved = _savedDraft;
    if (saved == null) return;
    SetupDraft? parsed;
    try {
      parsed = SetupDraft.fromJson(jsonDecode('${saved['draft']}'));
    } catch (_) {
      parsed = null;
    }
    if (parsed == null) {
      _toast('That draft could not be opened', 'Start a new setup instead.');
      return;
    }
    final draft = parsed;
    setState(() {
      _draft = draft;
      final phase = '${saved['phase'] ?? ''}';
      if (['batch', 'pens', 'allocate'].contains(phase)) _allocPhase = phase;
      _submitted = false;
      _serverErrors = {};
      _go('wizard', ((saved['step'] as num?)?.toInt() ?? 0).clamp(0, 4));
    });
  }

  void _startExistingFarm() {
    setState(() {
      _draft = SetupDraft(
        batches: [for (final b in _ctx.existingBatches) batchRowFromExisting(b)],
        houses: [for (final h in _ctx.existingHouses) houseRowFromExisting(h)],
      );
      _submitted = false;
      _serverErrors = {};
      _go('wizard', 0);
    });
    _clearSavedDraft();
  }

  void _generateHouses() {
    final n = int.tryParse(_penCount.trim());
    if (n == null || n < 1) return _toast('Nothing to create', 'Enter how many pens you need.');
    final start = int.tryParse((_penStartOverride ?? '$_suggestedPenStart').trim()) ?? 1;
    _edit(() {
      _draft.houses = [
        ..._draft.houses.where((h) => h.existingHouseId != null),
        ...generateHouseRows(count: n, prefix: _penPrefix, startNumber: start, capacity: _penCapacity, location: _penLocation),
      ];
    });
  }

  void _generateBatchRows() {
    final n = int.tryParse(_batchCount.trim());
    if (n == null || n < 1) return _toast('Nothing to create', 'Enter how many batches you have.');
    final start = int.tryParse((_batchStartOverride ?? '$_suggestedBatchStart').trim()) ?? 1;
    _edit(() {
      final keep = {for (final b in _draft.batches) if (b.existingBatchId != null) b.key};
      _draft.batches = [
        ..._draft.batches.where((b) => b.existingBatchId != null),
        ...generateBatches(
          count: n,
          prefix: _batchPrefix,
          codePrefix: _batchCodePrefix,
          startNumber: start,
          breed: _batchBreed,
          numberOfBirds: _batchBirds,
          startDate: _batchDate,
        ),
      ];
      // A replaced row's flocks would point at nothing.
      for (final f in _draft.flocks) {
        if (!keep.contains(f.batchKey)) f.batchKey = '';
      }
    });
  }

  int get _suggestedPenStart => nextStartNumber(_penPrefix, _ctx.existingHouses.map((h) => h.houseName));

  int get _suggestedBatchStart => [
        nextStartNumber(_batchPrefix, _ctx.existingBatches.map((b) => b.batchName)),
        nextStartNumber(_batchCodePrefix, _ctx.existingBatches.map((b) => b.batchCode)),
      ].reduce((a, b) => a > b ? a : b);

  void _removeBatch(int i) => _edit(() {
        final gone = _draft.batches.removeAt(i);
        for (final f in _draft.flocks) {
          if (f.batchKey == gone.key) f.batchKey = '';
        }
      });

  void _removeHouse(int i) {
    final gone = _draft.houses[i];
    final losing = _draft.flocks.where((f) => f.houseKey == gone.key).length;
    _edit(() {
      _draft.houses.removeAt(i);
      _draft.flocks.removeWhere((f) => f.houseKey == gone.key);
    });
    if (losing > 0) {
      _toast('${gone.houseName.isEmpty ? 'Pen' : gone.houseName} removed',
          '$losing flock${losing == 1 ? '' : 's'} allocated to it ${losing == 1 ? 'was' : 'were'} removed too.');
    }
  }

  void _removeFlock(int i) => _edit(() => _draft.flocks.removeAt(i));

  void _chooseBatch(String key) => _edit(() {
        _selectedBatchKey = key;
        _allocPhase = _draft.flocks.any((f) => f.batchKey == key) ? 'allocate' : 'pens';
      });

  FlockRow _newFlockFor(BatchRow? b, HouseRow house) => emptyFlock(_selectedBatchKey, house.key)
    ..name = defaultFlockName(b?.batchCode ?? '', house.houseName)
    ..startDate = b?.startDate ?? '';

  void _togglePen(String houseKey, bool on) {
    final b = _draft.batches.where((x) => x.key == _selectedBatchKey).firstOrNull;
    final house = _draft.houses.where((h) => h.key == houseKey).firstOrNull;
    _edit(() {
      if (!on) {
        _draft.flocks.removeWhere((f) => f.batchKey == _selectedBatchKey && f.houseKey == houseKey);
        return;
      }
      if (house == null || _draft.flocks.any((f) => f.batchKey == _selectedBatchKey && f.houseKey == houseKey)) return;
      _draft.flocks.add(_newFlockFor(b, house));
    });
  }

  void _selectAllPens(bool on) {
    if (_selectedBatchKey.isEmpty) return;
    if (!on) return _edit(() => _draft.flocks.removeWhere((f) => f.batchKey == _selectedBatchKey));
    final b = _draft.batches.where((x) => x.key == _selectedBatchKey).firstOrNull;
    _edit(() {
      final taken = {for (final f in _draft.flocks) if (f.batchKey == _selectedBatchKey) f.houseKey};
      _draft.flocks.addAll([
        for (final v in penOptions(houseRowViews(_draft, _ctx)))
          if (!taken.contains(v.row.key)) _newFlockFor(b, v.row),
      ]);
    });
  }

  String get _suggestedPenName {
    final numbers = [
      for (final h in _draft.houses)
        if (RegExp(r'^\s*pen\s+(\d+)\s*$', caseSensitive: false).firstMatch(h.houseName) case final m?) int.parse(m.group(1)!),
    ];
    return numbers.isEmpty ? '' : 'Pen ${numbers.reduce((a, b) => a > b ? a : b) + 1}';
  }

  Future<void> _newPen() async {
    final pens = await showNewPenDialog(
      context,
      suggestedName: _suggestedPenName,
      takenNames: [for (final h in _draft.houses) h.houseName],
    );
    if (pens == null || pens.isEmpty) return;
    final b = _draft.batches.where((x) => x.key == _selectedBatchKey).firstOrNull;
    final rows = [for (final p in pens) emptyHouse(p.capacity, p.location)..houseName = p.name];
    _edit(() {
      _draft.houses.addAll(rows);
      if (_selectedBatchKey.isNotEmpty) _draft.flocks.addAll([for (final r in rows) _newFlockFor(b, r)]);
    });
    _toast(
      pens.length == 1 ? '${pens.first.name} added' : '${pens.length} pens added',
      pens.length == 1
          ? 'It will be created when you finish the setup.'
          : '${pens.first.name} to ${pens.last.name}. They will be created when you finish the setup.',
    );
  }

  void _autoFill(String mode, BatchAllocationView active) {
    _edit(() {
      if (mode == 'even') {
        distributePensEvenly(_draft, active.batch.key, active.available);
      } else {
        fillPensToCapacity(_draft, _ctx, active.batch.key, active.available);
      }
    });
    _toast(mode == 'even' ? 'Birds spread evenly' : 'Pens filled to capacity',
        'Every number is editable — change whatever does not match the farm.');
  }

  /// A pen's capacity, from the note that revealed it. An EXISTING pen saves
  /// now (PUT /House/{id}); a new one is only edited in the draft.
  Future<void> _fixCapacity(String houseKey) async {
    final index = _draft.houses.indexWhere((h) => h.key == houseKey);
    if (index < 0) return;
    final row = _draft.houses[index];
    final load = houseLoad(houseKey, _draft, _ctx);
    await showPenCapacityDialog(
      context,
      penName: load?.label ?? row.houseName,
      capacity: load?.capacity,
      occupied: load?.occupied ?? 0,
      standing: load?.standing ?? 0,
      savesImmediately: row.existingHouseId != null,
      onSave: (capacity) async {
        if (row.existingHouseId == null) {
          _edit(() => row.capacity = '$capacity');
          _toast('Capacity updated',
              '${row.houseName.isEmpty ? 'The pen' : row.houseName} will be created holding ${fmtInt(capacity)}.');
          return;
        }
        if (_userId.isEmpty) throw StateError('Your session has expired. Sign in again.');
        try {
          await _client.put('/api/House/${row.existingHouseId}', body: {
            'UserId': _userId,
            'FarmId': _farmId,
            'HouseId': row.existingHouseId,
            'HouseName': row.houseName,
            'Capacity': capacity,
            'Location': row.location.isEmpty ? null : row.location,
          });
        } on ApiException catch (e) {
          throw StateError(e.message.isNotEmpty ? e.message : 'That pen could not be updated.');
        }
        await _reloadContext();
        _toast('Capacity updated', '${row.houseName} now holds ${fmtInt(capacity)} birds.');
      },
    );
  }

  /// A batch's bird count. An EXISTING batch is read back in full first and
  /// PUT whole, because the update overwrites every column.
  Future<void> _fixBatchSize(String batchKey) async {
    final v = batchAllocationViews(_draft, _ctx).where((x) => x.batch.key == batchKey).firstOrNull;
    if (v == null) return;
    final row = v.batch;
    final label = row.batchCode.isNotEmpty ? row.batchCode : row.batchName;
    await showBatchSizeDialog(
      context,
      batchLabel: label,
      batchBirds: v.batchBirds,
      previouslyAllocated: v.previouslyAllocated,
      thisAllocation: v.thisAllocation,
      savesImmediately: row.existingBatchId != null,
      onSave: (birds) async {
        if (row.existingBatchId == null) {
          _edit(() => row.numberOfBirds = '$birds');
          _toast('Bird count updated', '${row.batchCode.isEmpty ? 'The batch' : row.batchCode} will be created with ${fmtInt(birds)} birds.');
          return;
        }
        if (_userId.isEmpty) throw StateError('Your session has expired. Sign in again.');
        Map b;
        try {
          final got = await _client.get('/api/MainFlockBatch/${row.existingBatchId}', query: _scope);
          if (got is! Map) throw StateError('That batch could not be read.');
          b = got;
        } on ApiException catch (e) {
          throw StateError(e.message.isNotEmpty ? e.message : 'That batch could not be read.');
        }
        try {
          await _client.put('/api/MainFlockBatch/${row.existingBatchId}', body: {
            'BatchId': row.existingBatchId,
            'UserId': _userId,
            'FarmId': _farmId,
            'BatchName': b['batchName'],
            'BatchCode': b['batchCode'],
            'Breed': b['breed'],
            'StartDate': b['startDate'],
            'Status': b['status'],
            'CostPerChick': b['costPerChick'],
            'TotalCost': b['totalCost'],
            'AmountPaid': b['amountPaid'],
            'SupplierType': b['supplierType'],
            'SupplierId': b['supplierId'],
            'DollarConversionRate': b['dollarConversionRate'],
            'OrderPlacementDate': b['orderPlacementDate'],
            'EstimatedArrivalDate': b['estimatedArrivalDate'],
            'Notes': b['notes'],
            // The one thing being changed.
            'NumberOfBirds': birds,
          });
        } on ApiException catch (e) {
          throw StateError(e.message.isNotEmpty ? e.message : 'That batch could not be updated.');
        }
        await _reloadContext();
        _toast('Bird count updated', '${b['batchCode'] ?? label} now has ${fmtInt(birds)} birds.');
      },
    );
  }

  /// Re-read what the farm has, so houseLoad and the notes see a saved fix.
  Future<void> _reloadContext() async {
    final c = await _get('/api/PoultryFarmSetup/context');
    if (c is Map && mounted) setState(() => _ctx = SetupContext.fromServer(c, _ctx.businessDate));
  }

  ({String label, VoidCallback onTap})? _fixFor(SetupRowError e) {
    if (e.section == 'houses' && e.field == 'capacity') {
      if (e.index >= _draft.houses.length) return null;
      final row = _draft.houses[e.index];
      return (label: 'Update ${row.houseName.isEmpty ? 'this pen' : row.houseName}', onTap: () => _fixCapacity(row.key));
    }
    if (e.section == 'batches' && e.field == 'numberOfBirds') {
      if (e.index >= _draft.batches.length) return null;
      final row = _draft.batches[e.index];
      final name = row.batchCode.isNotEmpty ? row.batchCode : row.batchName.isNotEmpty ? row.batchName : 'this batch';
      return (label: 'Update $name', onTap: () => _fixBatchSize(row.key));
    }
    return null;
  }

  static String _sectionForStep(int step) => step == 0 ? 'houses' : step == 1 ? 'batches' : 'flocks';

  void _goNext() {
    final v = _validation;
    setState(() => _submitted = true);
    final blocking = v.errors.where((e) {
      if (e.index >= 0) return e.section == _sectionForStep(_step);
      if (e.field == 'flocks' && _step < 2) return false;
      return true;
    }).toList();
    if (blocking.isNotEmpty) {
      final setupError = v.errors.where((e) => e.index < 0).firstOrNull;
      _toast('Check the rows below',
          setupError?.message ?? '${blocking.length} row${blocking.length == 1 ? '' : 's'} need attention.');
      return;
    }
    _goToStep((_step + 1).clamp(0, 4));
  }

  /// Free movement both ways. Moving past Allocation pre-fills the
  /// reconciliation; arriving at Allocation resumes where the batch left off.
  void _goToStep(int target) {
    if (target == _step) return;
    _edit(() {
      if (target > _step && _step <= 2 && target > 2) seedReconciliation(_draft);
      if (target == 2) {
        final hasRows = _selectedBatchKey.isNotEmpty && _draft.flocks.any((f) => f.batchKey == _selectedBatchKey);
        _allocPhase = hasRows ? 'allocate' : _selectedBatchKey.isNotEmpty ? 'pens' : 'batch';
      }
      _submitted = false;
      _go('wizard', target);
    });
  }

  void _back() {
    if (_step == 0) {
      _clearSavedDraft();
      setState(() => _go('choose'));
    } else {
      _edit(() => _go('wizard', _step - 1));
    }
  }

  Future<void> _submit() async {
    final v = _validation;
    setState(() => _submitted = true);
    if (v.errors.isNotEmpty) {
      final setupError = v.errors.where((e) => e.index < 0).firstOrNull;
      _toast('Check the rows below', setupError?.message ?? 'Some rows still need attention.');
      return;
    }
    if (_userId.isEmpty) {
      _toast('Session issue', 'We could not confirm your farm or user. Please sign in again.');
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await _client.post('/api/PoultryFarmSetup/complete', body: toRequest(_draft, _ctx, _userId, _farmId));
      _saveTimer?.cancel();
      setState(() {
        _result = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
        _go('done');
      });
      await _clearSavedDraft();
      await _load(keepScreen: true);
    } on ApiException catch (e) {
      final body = e.body;
      final fromServer = <String, Map<int, Map<String, String>>>{};
      final errs = body is Map ? body['errors'] : null;
      if (errs is List) {
        for (final x in errs) {
          if (x is! Map) continue;
          final i = (x['index'] as num?)?.toInt() ?? -1;
          if (i < 0) continue;
          fromServer.putIfAbsent('${x['section']}', () => {}).putIfAbsent(i, () => {})['${x['field']}'] = '${x['message']}';
        }
      }
      setState(() => _serverErrors = fromServer);
      _toast('Nothing was created',
          e.message.isNotEmpty ? e.message : 'Your farm was not set up. Nothing was saved.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openLink(String label, String href, String? specKey) =>
      openNavLink(Navigator.of(context), NavLink(label, href, specKey), widget.session, widget.company);

  /// The phone's Back walks the wizard the way the web's history does.
  void _onBack() {
    if (_screen == 'wizard') {
      if (_step > 0) {
        _edit(() => _go('wizard', _step - 1));
      } else {
        setState(() => _go('choose'));
      }
    } else if (_screen == 'newBatch') {
      setState(() => _go('choose'));
    }
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-farm-setup');
    final trap = _screen == 'wizard' || _screen == 'newBatch';
    return PopScope(
      canPop: !trap,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: _slate50,
        appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Initial Farm Setup')),
        // In the bottom slot, not the body, so messages rise above it instead
        // of covering Continue.
        bottomNavigationBar: !_loading && _screen == 'wizard' ? _pinnedBar(summarize(_draft)) : null,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _screen == 'wizard'
                ? _wizard()
                : ListView(
                    key: ValueKey('screen-$_screen'),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                    children: _entry(),
                  ),
      ),
    );
  }

  Widget _intro() => const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text('Your opening farm position — what was true when tracking began.',
            style: TextStyle(fontSize: 13, color: _slate600)),
      );

  List<Widget> _entry() {
    final saved = _savedDraft;
    return [
      _intro(),
      if (saved != null && (_screen == 'choose' || _screen == 'completed')) ...[
        _savedDraftCard(saved),
        const SizedBox(height: 14),
      ],
      if (_screen == 'completed' && _status != null) _completedPanel(),
      if (_screen == 'choose') ..._chooseScreen(),
      if (_screen == 'newBatch') _newBatchScreen(),
      if (_screen == 'done' && _result != null) _doneScreen(),
    ];
  }

  Widget _savedDraftCard(Map<String, dynamic> saved) {
    String summary;
    try {
      final d = jsonDecode('${saved['draft']}') as Map;
      int n(String k) => d[k] is List ? (d[k] as List).length : 0;
      final b = n('batches'), h = n('houses'), f = n('flocks');
      final step = ((saved['step'] as num?)?.toInt() ?? 0).clamp(0, 4);
      summary = '$b batch${b == 1 ? '' : 'es'} · $h pen${h == 1 ? '' : 's'} · $f flock${f == 1 ? '' : 's'} — ${setupSteps[step]}';
    } catch (_) {
      summary = 'Saved on this farm.';
    }
    final at = fmtInstant(saved['updatedAt'], _offset);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _amber50,
        border: Border.all(color: _amber300, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('You have an unfinished setup', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(summary, style: const TextStyle(fontSize: 13, color: _slate700)),
        const SizedBox(height: 2),
        Text(
          'Last edited ${at.isEmpty ? 'recently' : at}'
          '${'${saved['updatedBy'] ?? ''}'.isNotEmpty ? ' by ${saved['updatedBy']}' : ''}.',
          style: const TextStyle(fontSize: 12, color: _slate600),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: AppButton(label: 'Discard', variant: AppButtonVariant.outline, onPressed: _clearSavedDraft)),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _amber600),
              onPressed: _resumeDraft,
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('Resume'),
            ),
          ),
        ]),
      ]),
    );
  }

  List<Widget> _chooseScreen() {
    final s = _status;
    int n(String k) => (s?[k] as num?)?.toInt() ?? 0;
    Widget option({
      required IconData icon,
      required Color iconColor,
      required String title,
      required String body,
      required Widget button,
    }) =>
        AppCard(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
            ]),
            const SizedBox(height: 8),
            Text(body, style: const TextStyle(fontSize: 13, color: _slate600)),
            const SizedBox(height: 12),
            button,
          ]),
        );
    return [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Set Up Your Farm', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text(
            "Tell us about the birds currently on your farm. We'll help create your batches, houses/pens and flocks, "
            'and establish your correct starting bird position.',
            style: TextStyle(fontSize: 13, color: _slate600),
          ),
          if (s != null && s['looksEmpty'] == false) ...[
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded, size: 16, color: _amber700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'This company already has ${n('existingBatches')} batch${n('existingBatches') == 1 ? '' : 'es'}, '
                  '${n('existingHouses')} house${n('existingHouses') == 1 ? '' : 's'} and '
                  '${n('existingFlocks')} flock${n('existingFlocks') == 1 ? '' : 's'}. The wizard will offer them for '
                  'reuse rather than creating them again.',
                  style: const TextStyle(fontSize: 13, color: _amber700),
                ),
              ),
            ]),
          ],
        ]),
      ),
      const SizedBox(height: 12),
      option(
        icon: Icons.egg_outlined,
        iconColor: _emerald600,
        title: 'I already have birds on my farm',
        body: "Use this if your farm has been operating before you started using the system. We'll record what is "
            'standing in each pen today and reconcile it against what was originally placed — without pretending those '
            'losses happened today.',
        button: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: _blue600),
          onPressed: _startExistingFarm,
          icon: const Icon(Icons.arrow_forward, size: 16),
          label: const Text('Quick Farm Setup'),
        ),
      ),
      const SizedBox(height: 12),
      option(
        icon: Icons.add,
        iconColor: _slate500,
        title: "I'm starting with a new batch of chicks",
        body: 'Use this if these birds are newly purchased and there is no historical farm position to reconstruct. '
            'That is just the ordinary workflow — no reconciliation needed.',
        button: AppButton(
          label: 'Show me how',
          icon: Icons.arrow_forward,
          variant: AppButtonVariant.outline,
          onPressed: () => setState(() => _go('newBatch')),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('Prefer to do it yourself? ', style: TextStyle(fontSize: 13, color: _slate500)),
        InkWell(
          onTap: () => _openLink('Flock Purchases (Batches)', '/flock-batch', 'flock'),
          child: const Text('Set Up Manually', style: TextStyle(fontSize: 13, color: _blue600)),
        ),
        const Text(' using Flock Purchases, Houses and Flock Groups.', style: TextStyle(fontSize: 13, color: _slate500)),
      ]),
    ];
  }

  Widget _newBatchScreen() => AppCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Starting with a new batch', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Nothing to reconstruct — these birds start their life here. Use the ordinary workflow:',
              style: TextStyle(color: _slate600)),
          const SizedBox(height: 8),
          const Text.rich(TextSpan(style: TextStyle(color: _slate700, height: 1.5), children: [
            TextSpan(text: '1. Record the purchase in '),
            TextSpan(text: 'Flock Purchases', style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: '.\n2. Add your houses/pens if you have not already — the batch tool can do it for you.\n3. Use '),
            TextSpan(text: 'Divide Into Flocks', style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ' to spread the batch across your pens.'),
          ])),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _blue600),
              onPressed: () => _openLink('Flock Purchases (Batches)', '/flock-batch', 'flock'),
              child: const Text('Go to Flock Purchases'),
            ),
            AppButton(
              label: 'Go to Houses',
              variant: AppButtonVariant.outline,
              onPressed: () => _openLink('Houses', '/houses', 'house'),
            ),
            AppButton(label: 'Back', variant: AppButtonVariant.ghost, onPressed: () => setState(() => _go('choose'))),
          ]),
        ]),
      );

  Widget _doneScreen() {
    final r = _result!;
    int n(String k) => (r[k] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: _emerald50, border: Border.all(color: _emerald200), borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        const Icon(Icons.check_circle_outline, size: 40, color: _emerald600),
        const SizedBox(height: 6),
        const Text('Your farm is ready.', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: _emerald900)),
        const SizedBox(height: 6),
        Text(
          '${n('batchesCreated')} batch${n('batchesCreated') == 1 ? '' : 'es'} · '
          '${n('housesCreated')} house${n('housesCreated') == 1 ? '' : 's'}/pens · '
          '${n('flocksCreated')} flock${n('flocksCreated') == 1 ? '' : 's'} · '
          '${fmtInt(n('openingLiveBirds'))} current birds',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _emerald800),
        ),
        if (n('historicalReduction') > 0) ...[
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(style: const TextStyle(fontSize: 13, color: _emerald800), children: [
              TextSpan(text: '${fmtInt(n('historicalReduction'))} birds were recorded as an opening historical reduction — '),
              const TextSpan(text: 'not', style: TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(text: " as today's mortality."),
            ]),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _emerald600),
            onPressed: () => _openLink('Production Records', '/production-records', 'production-records'),
            child: const Text('Start Recording Production'),
          ),
          AppButton(
            label: 'View Opening Farm Position',
            variant: AppButtonVariant.outline,
            onPressed: () => setState(() => _go('completed')),
          ),
        ]),
      ]),
    );
  }

  Widget _completedPanel() {
    final s = _status!;
    final o = _opening;
    int n(Map? m, String k) => (m?[k] as num?)?.toInt() ?? 0;
    Widget link(String label, String href, String spec) => InkWell(
          onTap: () => _openLink(label, href, spec),
          child: Text(label, style: const TextStyle(fontSize: 13, color: _blue600)),
        );
    final positions = [for (final p in (o?['positions'] is List ? o!['positions'] as List : const [])) if (p is Map) p];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: _blue50, border: Border.all(color: _blue300, width: 2), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Do another bulk setup', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text(
            'Built new pens, or bought another batch? Run the setup again to add and allocate them in one go. Your '
            'existing pens, batches and flocks are kept — nothing here is created twice.',
            style: TextStyle(fontSize: 13, color: _slate600),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _blue600, minimumSize: const Size.fromHeight(46)),
            onPressed: _startExistingFarm,
            icon: const Icon(Icons.add),
            label: const Text('Do another bulk setup', style: TextStyle(fontSize: 15)),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _emerald200), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [
            Icon(Icons.check_circle_outline, size: 20, color: _emerald600),
            SizedBox(width: 8),
            Expanded(child: Text('Initial Farm Setup Completed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 10),
          _grid([
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Completed', style: TextStyle(fontSize: 12, color: _slate500)),
              Text(toBusinessDate(s['completedBusinessDate']) ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            _Stat('Batches', n(s, 'batchCount'), tone: 'blue', small: true),
            _Stat('Flocks', n(s, 'flockCount'), tone: 'blue', small: true),
            _Stat('Opening live birds', n(s, 'openingLiveBirds'), tone: 'emerald', small: true),
            _Stat('Historical reconciliation', n(s, 'historicalReduction'), tone: 'amber', small: true),
          ]),
          const SizedBox(height: 10),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('Day-to-day work happens on ', style: TextStyle(fontSize: 13, color: _slate600)),
            link('Flock Purchases', '/flock-batch', 'flock'),
            const Text(', ', style: TextStyle(fontSize: 13, color: _slate600)),
            link('Houses', '/houses', 'house'),
            const Text(', ', style: TextStyle(fontSize: 13, color: _slate600)),
            link('Flock Groups', '/flocks', 'flocks'),
            const Text(' and ', style: TextStyle(fontSize: 13, color: _slate600)),
            link('Production Records', '/production-records', 'production-records'),
            const Text('.', style: TextStyle(fontSize: 13, color: _slate600)),
          ]),
        ]),
      ),
      if (o != null && n(o, 'flockCount') > 0) ...[
        const SizedBox(height: 14),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Row(children: [
              Icon(Icons.assignment_outlined, size: 20, color: _slate600),
              SizedBox(width: 8),
              Text('Opening Farm Position', style: TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            const Text.rich(TextSpan(style: TextStyle(fontSize: 13, color: _slate600), children: [
              TextSpan(text: 'What was true when tracking began. These figures are '),
              TextSpan(text: 'not', style: TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(
                  text: ' operational events: none of them appears in Production Records, in Total Deaths, or in any '
                      'dated mortality report.'),
            ])),
            const SizedBox(height: 10),
            _grid([
              _Stat('Birds originally placed', n(o, 'originallyPlaced'), tone: 'blue'),
              _Stat('Opening live birds', n(o, 'openingLiveBirds'), tone: 'emerald'),
              _Stat('Historical reduction', n(o, 'historicalReduction'), tone: 'amber'),
              _Stat('Opening historical mortality', n(o, 'historicalMortality'), tone: 'rose'),
            ]),
            const SizedBox(height: 8),
            _grid([
              _Stat('Sold', n(o, 'historicalSold'), small: true),
              _Stat('Culled', n(o, 'historicalCulled'), small: true),
              _Stat('Transferred', n(o, 'historicalTransferred'), small: true),
              _Stat('Other / unknown', n(o, 'otherAdjustment'), small: true),
            ]),
            if (n(o, 'otherAdjustment') > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${fmtInt(n(o, 'otherAdjustment'))} birds have no stated cause across ${n(o, 'flocksWithUnknownHistory')} '
                'flock${n(o, 'flocksWithUnknownHistory') == 1 ? '' : 's'}. They are counted as an opening adjustment, never '
                'as mortality — known lifetime mortality is the opening mortality above plus whatever has been recorded since.',
                style: const TextStyle(fontSize: 12, color: _slate500),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(8)),
              child: Column(children: [
                for (final (i, p) in positions.indexed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: _slate100))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text('${p['flockName'] ?? 'Flock #${p['flockId']}'}', style: const TextStyle(fontWeight: FontWeight.w500)),
                        if (p['startDateEstimated'] == true) const _Badge('age estimated', _slate300, _slate500),
                      ]),
                      Text.rich(TextSpan(style: const TextStyle(fontSize: 13, color: _slate600), children: [
                        TextSpan(text: 'placed ${fmtInt(n(p, 'originallyPlaced'))} · opening ${fmtInt(n(p, 'openingLiveBirds'))}'),
                        if (n(p, 'historicalReduction') > 0)
                          TextSpan(
                            text: ' · reduction ${fmtInt(n(p, 'historicalReduction'))}'
                                '${p['historyKnown'] == true ? ' (mortality ${fmtInt(n(p, 'historicalMortality'))})' : ' (unknown)'}',
                            style: const TextStyle(color: _amber700),
                          ),
                      ])),
                    ]),
                  ),
              ]),
            ),
          ]),
        ),
      ],
      if (o != null && n(o, 'flockCount') == 0) ...[
        const SizedBox(height: 14),
        const AppCard(
          padding: EdgeInsets.all(18),
          child: Column(children: [
            Icon(Icons.home_outlined, size: 40, color: _slate400),
            SizedBox(height: 6),
            Text(
              'No opening positions were recorded — this farm started with new birds, so there was no history to reconstruct.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _slate600),
            ),
          ]),
        ),
      ],
    ]);
  }

  // --------------------------------------------------------------- wizard

  Widget _wizard() {
    final v = _validation;
    final fieldErrors = errorsBySection(v.errors);
    final totals = summarize(_draft);
    // A step opens at its top, not where the last one was scrolled to.
    return ListView(
      key: ValueKey('step-$_step'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
      children: [
        _intro(),
        _stepBar(),
        const SizedBox(height: 14),
        switch (_step) {
          0 => _housesStep(fieldErrors),
          1 => _batchesStep(fieldErrors),
          2 => _flocksStep(fieldErrors),
          3 => _reconcileStep(),
          _ => _reviewStep(v, totals),
        },
      ],
    );
  }

  /// Phones: the step name, a progress bar and five numbered buttons.
  Widget _stepBar() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Text(setupSteps[_step], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
          Text('Step ${_step + 1} of ${setupSteps.length}', style: const TextStyle(fontSize: 12, color: _slate500)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: (_step + 1) / setupSteps.length,
            minHeight: 6,
            color: _blue600,
            backgroundColor: _slate200,
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          for (var i = 0; i < setupSteps.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                label: 'Go to ${setupSteps[i]}',
                button: true,
                child: InkWell(
                  onTap: () => _goToStep(i),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == _step ? _blue600 : i < _step ? _blue100 : _slate100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${i + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: i == _step ? Colors.white : i < _step ? _blue700 : _slate500,
                        )),
                  ),
                ),
              ),
            ),
          ],
        ]),
      ]);

  Widget _pinnedBar(SetupTotals totals) {
    final draftNote = switch (_draftState) {
      'saving' => 'Saving…',
      'saved' => 'Saved',
      'error' => 'Not saved — check your connection',
      _ => 'Step ${_step + 1} of ${setupSteps.length}',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _slate200)),
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_step >= 2 && _draft.flocks.isNotEmpty) ...[
            Row(children: [
              _running('Placed', totals.originallyPlaced, 'slate'),
              const SizedBox(width: 6),
              _running('Live', totals.openingLiveBirds, 'emerald'),
              const SizedBox(width: 6),
              _running('Reduction', totals.historicalReduction, 'amber'),
            ]),
            if (totals.flocksWithUnknownHistory > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${totals.flocksWithUnknownHistory} flock${totals.flocksWithUnknownHistory == 1 ? '' : 's'} with unknown history',
                  style: const TextStyle(fontSize: 12, color: _slate500),
                ),
              ),
            const Divider(height: 16),
          ],
          Row(children: [
            Flexible(
              child: TextButton.icon(
                onPressed: _saving ? null : _back,
                icon: const Icon(Icons.arrow_back, size: 16),
                label: Text(_step == 0 ? 'Cancel' : 'Back & Edit', overflow: TextOverflow.ellipsis),
              ),
            ),
            const Spacer(),
            if (_step < 4)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _blue600),
                onPressed: _goNext,
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('Continue'),
              )
            else
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _emerald600),
                onPressed: _saving ? null : _submit,
                child: Text(_saving ? 'Setting up…' : 'Complete Farm Setup'),
              ),
          ]),
          Text(draftNote,
              textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: _slate500)),
        ]),
      ),
    );
  }

  Widget _running(String label, int value, String tone) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: _slate200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label.toUpperCase(),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: .5, color: _slate500)),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(fmtInt(value), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _tones[tone])),
            ),
          ]),
        ),
      );

  // ---------------------------------------------------------- step 0

  Widget _housesStep(Map<String, Map<int, Map<String, String>>> fe) {
    final views = houseRowViews(_draft, _ctx);
    final visible = _houseFilter == 'new'
        ? [for (final v in views) if (!v.isExisting) v]
        : visibleHouseRows(views, _houseFilter == 'all');
    final sum = summarizeHouseRows(views);
    final penStart = _penStartOverride ?? '$_suggestedPenStart';
    final summary = _houseFilter == 'all'
        ? sum.occupied > 0
            ? 'Showing all ${fmtInt(sum.total)} pens, including ${fmtInt(sum.occupied)} that already ${sum.occupied == 1 ? 'holds' : 'hold'} birds.'
            : 'Showing all ${fmtInt(sum.total)} pens.'
        : _houseFilter == 'new'
            ? 'Your ${fmtInt(sum.existing)} existing ${sum.existing == 1 ? 'pen is' : 'pens are'} hidden — showing only the new ones.'
            : sum.occupied > 0
                ? 'Showing empty pens only — ${fmtInt(sum.occupied)} that already ${sum.occupied == 1 ? 'holds' : 'hold'} birds ${sum.occupied == 1 ? 'is' : 'are'} hidden.'
                : 'Showing empty pens only.';
    return _Section(
      icon: Icons.home_outlined,
      title: 'Where are your birds housed?',
      description:
          'Create a run of new pens, then edit any of them. Pens you already have are listed so you can allocate to them — this step never deletes a pen from your farm.',
      children: [
        _GeneratorBox(children: [
          _Field(label: 'Number of Pens', child: _number('gen.penCount', _penCount, (s) => setState(() => _penCount = s))),
          _Field(label: 'Naming Prefix', child: _text('gen.penPrefix', _penPrefix, (s) => setState(() => _penPrefix = s), hint: 'Pen')),
          _Field(
            label: 'Starting Number',
            hint: _penStartOverride == null && _suggestedPenStart > 1
                ? 'Continues after your existing ${_penPrefix.trim().isEmpty ? 'numbered' : _penPrefix.trim()} pens'
                : null,
            child: _number('gen.penStart', penStart,
                (s) => setState(() => _penStartOverride = s.trim().isEmpty ? null : s), hint: '$_suggestedPenStart'),
          ),
          _Field(
              label: 'Default Capacity',
              child: _number('gen.penCapacity', _penCapacity, (s) => setState(() => _penCapacity = s), hint: '5000')),
          _Field(
              label: 'Default Location',
              child: _text('gen.penLocation', _penLocation, (s) => setState(() => _penLocation = s), hint: 'Layer House A')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _indigo600),
            onPressed: _generateHouses,
            icon: const Icon(Icons.auto_fix_high, size: 16),
            label: const Text('Create New Houses/Pens'),
          ),
          const Text('Replaces the new rows below; houses you already have are kept. Everything stays editable.',
              style: TextStyle(fontSize: 12, color: _slate500)),
        ]),
        if (_draft.houses.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _slate50, border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(summary, style: const TextStyle(fontSize: 13, color: _slate600)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (value, label) in [
                  ('all', 'All houses/pens (${fmtInt(sum.total)})'),
                  ('empty', 'Empty houses/pens (${fmtInt(sum.total - sum.occupied)})'),
                  ('new', 'Hide existing (${fmtInt(sum.existing)})'),
                ])
                  _Pill(label: label, on: _houseFilter == value, onTap: () => setState(() => _houseFilter = value)),
              ]),
            ]),
          ),
        if (_draft.houses.isEmpty)
          const Text('No houses/pens yet. Create some above, or add one row at a time.',
              style: TextStyle(fontSize: 13, color: _slate600)),
        if (_draft.houses.isNotEmpty && visible.isEmpty)
          Text(
            _houseFilter == 'new'
                ? 'No new pens yet. Create some above, or choose “All houses/pens” to see the ones you have.'
                : 'None of your pens are empty. Add a new one above, or choose “All houses/pens” to see them.',
            style: const TextStyle(fontSize: 13, color: _slate600),
          ),
        for (final hv in visible)
          () {
            final h = hv.row, i = hv.index, load = hv.load;
            return _RowCard(
              index: i,
              invalid: _rowInvalid(fe, 'houses', i),
              header: _RowHeader(
                label: h.houseName.isEmpty ? 'House ${i + 1}' : h.houseName,
                badge: hv.isExisting ? const _Badge('Existing', _slate200, _slate700, filled: true) : const _Badge('New', _blue300, _blue700),
                onRemove: hv.isExisting ? null : () => _removeHouse(i),
              ),
              children: [
                _Field(
                  label: 'House/Pen Name *',
                  error: _errorFor(fe, 'houses', i, 'houseName'),
                  hint: load == null || !hv.isExisting || load.activeFlocks == 0
                      ? null
                      : 'Holds ${fmtInt(load.occupied)} in ${load.activeFlocks} flock${load.activeFlocks == 1 ? '' : 's'}',
                  child: _text('h.${h.key}.name', h.houseName, (s) => _edit(() => h.houseName = s),
                      hint: 'Pen 1', enabled: !hv.isExisting),
                ),
                _Field(
                  label: 'Capacity',
                  error: _errorFor(fe, 'houses', i, 'capacity'),
                  child: _number('h.${h.key}.capacity', h.capacity, (s) => _edit(() => h.capacity = s), hint: '5000'),
                ),
                _Field(
                  label: 'Location',
                  child: _text('h.${h.key}.location', h.location, (s) => _edit(() => h.location = s), hint: 'Layer House A'),
                ),
              ],
            );
          }(),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: 'Add Another Row',
            icon: Icons.add,
            variant: AppButtonVariant.outline,
            size: AppButtonSize.sm,
            onPressed: () => _edit(() => _draft.houses.insert(0, emptyHouse(_penCapacity, _penLocation))),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------- step 1

  Widget _batchesStep(Map<String, Map<int, Map<String, String>>> fe) {
    final edits = [for (final (i, b) in _draft.batches.indexed) (row: b, index: i, isExisting: b.existingBatchId != null)];
    final existingCount = edits.where((e) => e.isExisting).length;
    final visible = _showExistingBatches ? edits : [for (final e in edits) if (!e.isExisting) e];
    final batchStart = _batchStartOverride ?? '$_suggestedBatchStart';
    final known = _knownBreeds;
    return _Section(
      icon: Icons.inventory_2_outlined,
      title: 'What batches/groups of birds do you currently have?',
      description:
          'Create a run of new batches, then edit any of them. Purchase cost and supplier are optional — if you do not know what you paid, leave them blank. Nothing here posts cash or revenue for a historical purchase.',
      children: [
        _GeneratorBox(children: [
          _Field(label: 'Number of Batches', child: _number('gen.batchCount', _batchCount, (s) => setState(() => _batchCount = s))),
          _Field(label: 'Name Prefix', child: _text('gen.batchPrefix', _batchPrefix, (s) => setState(() => _batchPrefix = s), hint: 'Batch')),
          _Field(
              label: 'Code Prefix',
              child: _text('gen.batchCodePrefix', _batchCodePrefix, (s) => setState(() => _batchCodePrefix = s), hint: 'B')),
          _Field(
            label: 'Starting Number',
            hint: _batchStartOverride == null && _suggestedBatchStart > 1 ? 'Continues after your existing batches' : null,
            child: _number('gen.batchStart', batchStart,
                (s) => setState(() => _batchStartOverride = s.trim().isEmpty ? null : s), hint: '$_suggestedBatchStart'),
          ),
          _Field(
            label: 'Default Breed',
            child: BreedPicker(
                value: _batchBreed, known: known, hintText: 'Pick a breed', onChanged: (b) => setState(() => _batchBreed = b)),
          ),
          _Field(label: 'Default Birds', child: _number('gen.batchBirds', _batchBirds, (s) => setState(() => _batchBirds = s))),
          _Field(label: 'Default Arrival Date', child: _date(_batchDate, (s) => setState(() => _batchDate = s))),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _blue600),
            onPressed: _generateBatchRows,
            icon: const Icon(Icons.auto_fix_high, size: 16),
            label: const Text('Create New Batches'),
          ),
          const Text('Replaces the new rows below; batches you already have are kept. Everything stays editable.',
              style: TextStyle(fontSize: 12, color: _slate500)),
        ]),
        const _InfoBox(
          strong: 'Complete batch information now.',
          text: ' You can skip the optional purchase details and add them later, but entering them now means your batch '
              'history, supplier and cost reporting are complete from the start.',
        ),
        if (existingCount > 0)
          AppCheckbox(
            value: _showExistingBatches,
            onChanged: (v) => setState(() => _showExistingBatches = v),
            label: 'Show the ${fmtInt(existingCount)} batch${existingCount == 1 ? '' : 'es'} you already have',
          ),
        if (visible.isEmpty)
          const Text('No new batches yet. Create some above, or add one at a time.', style: TextStyle(fontSize: 13, color: _slate600)),
        for (final e in visible) _batchCard(fe, e.row, e.index, e.isExisting, known),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: 'Add Another Batch',
            icon: Icons.add,
            variant: AppButtonVariant.outline,
            size: AppButtonSize.sm,
            onPressed: () => _edit(() => _draft.batches.insert(0, emptyBatch())),
          ),
        ),
      ],
    );
  }

  Widget _batchCard(Map<String, Map<int, Map<String, String>>> fe, BatchRow b, int i, bool existing, List<String> known) {
    final id = 'b.${b.key}';
    void costChange({String? cost, String? birds}) => _edit(() {
          if (cost != null) b.costPerChick = cost;
          if (birds != null) b.numberOfBirds = birds;
          final derived = deriveTotalCost(b.costPerChick, b.numberOfBirds);
          if (derived.isNotEmpty) b.totalCost = derived;
        });
    final supplierItems = [
      const AppSelectItem(value: 'none', label: 'No supplier'),
      for (final s in _suppliers)
        if (s['supplierId'] != null) AppSelectItem(value: '${s['supplierId']}', label: '${s['name'] ?? s['supplierId']}'),
    ];
    final accountItems = [
      AppSelectItem(value: 'none', label: b.isHistorical ? 'None' : 'None (no cash movement)'),
      for (final a in _cashAccounts)
        if (a['poultryCashAccountId'] != null)
          AppSelectItem(
            value: '${a['poultryCashAccountId']}',
            label: '${a['accountName'] ?? ''} (${_money2((a['currentBalance'] as num?) ?? 0)})',
          ),
    ];
    return _RowCard(
      index: i,
      invalid: _rowInvalid(fe, 'batches', i),
      header: _RowHeader(
        label: b.batchCode.isNotEmpty ? b.batchCode : b.batchName.isNotEmpty ? b.batchName : 'Batch ${i + 1}',
        badge: existing ? const _Badge('Existing', _slate200, _slate700, filled: true) : const _Badge('New', _blue300, _blue700),
        onRemove: () => _removeBatch(i),
        removeLabel: 'Remove batch',
      ),
      children: [
        if (!existing)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _slate50, border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const _SectionLabel('Where did these birds come from?'),
              const SizedBox(height: 6),
              _RadioRow(
                checked: b.isHistorical,
                onSelect: () => _edit(() => b.isHistorical = true),
                title: 'I already had these birds',
                detail:
                    "Bought before you started using PoultryMaster. Nothing is posted to today's expenses or cash — what you still owe is still recorded.",
              ),
              const SizedBox(height: 6),
              _RadioRow(
                checked: !b.isHistorical,
                onSelect: () => _edit(() => b.isHistorical = false),
                title: 'I am buying these birds now',
                detail: 'A real purchase happening now. Posts exactly as Flock Purchases would — expense, supplier balance and cash.',
              ),
            ]),
          ),
        const _SectionLabel('Batch details'),
        _Field(
          label: 'Batch Name *',
          error: _errorFor(fe, 'batches', i, 'batchName'),
          child: _text('$id.name', b.batchName, (s) => _edit(() => b.batchName = s),
              hint: 'e.g., Batch A - Rhode Island Reds', enabled: !existing),
        ),
        _Field(
          label: 'Batch Code *',
          error: _errorFor(fe, 'batches', i, 'batchCode'),
          child: _text('$id.code', b.batchCode, (s) => _edit(() => b.batchCode = s), hint: 'e.g., B-001', enabled: !existing),
        ),
        _Field(
          label: 'Breed',
          error: _errorFor(fe, 'batches', i, 'breed'),
          child: BreedPicker(value: b.breed, known: known, enabled: !existing, onChanged: (v) => _edit(() => b.breed = v)),
        ),
        _Field(
          label: 'Start Date *',
          error: _errorFor(fe, 'batches', i, 'startDate'),
          child: _date(b.startDate, (s) => _edit(() => b.startDate = s), enabled: !existing),
        ),
        _Field(
          label: 'Number of Birds *',
          error: _errorFor(fe, 'batches', i, 'numberOfBirds'),
          child: _number('$id.birds', b.numberOfBirds, (s) => costChange(birds: s), hint: 'e.g., 100', enabled: !existing),
        ),
        if (!existing && b.isHistorical)
          const Text('Every one of these birds must end up in a pen — they are standing on your farm today.',
              style: TextStyle(fontSize: 12, color: _slate500)),
        if (!existing) ...[
          const _SectionLabel('Purchase details', suffix: ' — optional'),
          _Field(
            label: 'Cost Per Chick',
            child: _number('$id.cost', b.costPerChick, (s) => costChange(cost: s), decimal: true),
          ),
          _Field(
            label: 'Total Cost',
            child: _number('$id.total', b.totalCost, (s) => _edit(() => b.totalCost = s), decimal: true, hint: 'Auto-calculated'),
          ),
          _Field(
            label: 'Amount Paid Now',
            hint: b.isHistorical
                ? 'Paid before you started tracking — posts no expense, but sets what you still owe.'
                : 'Part payment is fine — pay the balance later by editing the batch.',
            child: _number('$id.paid', b.amountPaid, (s) => _edit(() => b.amountPaid = s), decimal: true),
          ),
          _Field(label: 'Balance', child: _ReadOnlyBox(fmtNum(batchBalance(b.totalCost, b.amountPaid), 3))),
          _Field(
            label: 'Type',
            child: AppSelect<String>(
              value: b.supplierType.isEmpty ? 'local' : b.supplierType,
              items: const [AppSelectItem(value: 'local', label: 'Local'), AppSelectItem(value: 'foreign', label: 'Foreign')],
              onChanged: (v) => _edit(() => b.supplierType = v ?? 'local'),
            ),
          ),
          _Field(
            label: 'Supplier',
            child: AppSelect<String>(
              value: b.supplierId == null ? 'none' : '${b.supplierId}',
              hintText: _suppliers.isEmpty ? 'No suppliers found' : 'No supplier',
              items: supplierItems,
              onChanged: (v) => _edit(() => b.supplierId = v == null || v == 'none' ? null : int.tryParse(v)),
            ),
          ),
          if (b.supplierType == 'foreign' || b.dollarConversionRate.trim().isNotEmpty)
            _Field(
              label: 'Dollar Conversion Rate',
              child: _number('$id.rate', b.dollarConversionRate, (s) => _edit(() => b.dollarConversionRate = s), decimal: true),
            ),
          const _SectionLabel('Order & delivery', suffix: ' — optional'),
          _Field(
            label: 'Order Placement Date',
            hint: 'When you placed the order with the supplier.',
            child: _date(b.orderPlacementDate, (s) => _edit(() => b.orderPlacementDate = s)),
          ),
          _Field(
            label: 'Estimated Arrival Date',
            hint: 'When the birds are expected to arrive.',
            child: _date(b.estimatedArrivalDate, (s) => _edit(() => b.estimatedArrivalDate = s)),
          ),
          _Field(
            label: b.isHistorical ? 'Paid from cash account' : 'Pay from cash account',
            hint: b.isHistorical
                ? "Recorded only. That money left before you started tracking, so the account's balance is not changed."
                : "The amount paid comes out of this account's balance.",
            child: AppSelect<String>(
              value: b.poultryCashAccountId == null ? 'none' : '${b.poultryCashAccountId}',
              hintText: 'None',
              items: accountItems,
              onChanged: (v) => _edit(() => b.poultryCashAccountId = v == null || v == 'none' ? null : int.tryParse(v)),
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------- step 2

  Widget _flocksStep(Map<String, Map<int, Map<String, String>>> fe) {
    final views = batchAllocationViews(_draft, _ctx);
    final visible = visibleBatchRows(views, _showAllBatches, _selectedBatchKey.isEmpty ? null : _selectedBatchKey);
    final sum = summarizeBatchRows(views);
    final active = views.where((v) => v.batch.key == _selectedBatchKey).firstOrNull;
    final activeFlocks = [
      for (final (i, f) in _draft.flocks.indexed)
        if (f.batchKey == _selectedBatchKey) (row: f, index: i),
    ];
    final houseViews = houseRowViews(_draft, _ctx);
    final allocatable = penOptions(houseViews);
    final pensIn = {for (final x in activeFlocks) if (x.row.houseKey.isNotEmpty) x.row.houseKey};
    final others = [for (final v in visible) if (v.batch.key != _selectedBatchKey) v];
    final nextBatch = others.where((v) => v.status == 'over').firstOrNull ?? others.where((v) => v.remaining > 0).firstOrNull;
    final existingFlocks = active?.batch.existingBatchId == null
        ? const <ExistingFlock>[]
        : [for (final f in _ctx.existingFlocks) if (f.batchId == active!.batch.existingBatchId) f];
    String batchLabel(BatchAllocationView v) =>
        v.batch.batchCode.isNotEmpty ? v.batch.batchCode : v.batch.batchName.isNotEmpty ? v.batch.batchName : 'Batch ${v.index + 1}';

    return _Section(
      icon: Icons.egg_outlined,
      title: 'What is in each house/pen today?',
      description:
          'Originally placed is what went into the pen. Current live birds is what is standing there now — that is the number tracking starts from.',
      children: [
        if (_allocPhase == 'batch')
          _BluePanel(
            title: 'Select a Batch',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (visible.isEmpty)
                const Text('Every batch is fully allocated. Tick “Show all batches” to look at one anyway.',
                    style: TextStyle(fontSize: 13, color: _slate600))
              else ...[
                const Text('Batch', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                AppSelect<String>(
                  value: _selectedBatchKey.isEmpty ? null : _selectedBatchKey,
                  hintText: 'Choose the batch to divide',
                  items: [
                    for (final v in visible)
                      AppSelectItem(
                        value: v.batch.key,
                        label: '${batchLabel(v)}'
                            '${v.batch.batchName.isNotEmpty && v.batch.batchCode.isNotEmpty ? ' · ${v.batch.batchName}' : ''}'
                            ' · ${v.status == 'over' ? '${fmtInt(v.overBy)} birds too many' : '${fmtInt(v.remaining)} of ${fmtInt(v.batchBirds)} birds left'}',
                      ),
                  ],
                  onChanged: (k) {
                    if (k != null) _chooseBatch(k);
                  },
                ),
                const SizedBox(height: 4),
                const Text('Pick the batch whose birds you are placing. You will choose the pens next.',
                    style: TextStyle(fontSize: 12, color: _slate500)),
              ],
              if (sum.hidden > 0)
                AppCheckbox(
                  value: _showAllBatches,
                  onChanged: (v) => setState(() => _showAllBatches = v),
                  label: 'Show all batches (${sum.hidden} fully allocated)',
                ),
            ]),
          ),
        if (active != null && _allocPhase != 'batch') ...[
          _BluePanel(
            title: 'Selected Batch',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Batch', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              _ReadOnlyBox([
                batchLabel(active),
                active.batch.batchName.isNotEmpty && active.batch.batchCode.isNotEmpty ? active.batch.batchName : '',
                active.batch.breed,
                '${fmtInt(active.batchBirds)} birds',
                active.batch.startDate.isNotEmpty ? 'started ${active.batch.startDate}' : '',
              ].where((x) => x.isNotEmpty).join(' · ')),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  label: 'Change batch',
                  variant: AppButtonVariant.outline,
                  size: AppButtonSize.sm,
                  onPressed: () => _edit(() => _allocPhase = 'batch'),
                ),
              ),
            ]),
          ),
          _batchSummary(active, activeFlocks.length, houseViews, allocatable, pensIn),
        ],
        if (_allocPhase == 'allocate' && active != null) ...[
          Container(
            decoration: BoxDecoration(border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                color: _indigo600,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: const Text('Allocation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(10),
                child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  AppButton(
                    label: 'Fill pens to capacity',
                    icon: Icons.auto_fix_high,
                    variant: AppButtonVariant.outline,
                    size: AppButtonSize.sm,
                    onPressed: activeFlocks.isEmpty || active.available == 0 ? null : () => _autoFill('capacity', active),
                  ),
                  AppButton(
                    label: 'Spread evenly',
                    icon: Icons.auto_fix_high,
                    variant: AppButtonVariant.outline,
                    size: AppButtonSize.sm,
                    onPressed: activeFlocks.isEmpty || active.available == 0 ? null : () => _autoFill('even', active),
                  ),
                  AppButton(
                    label: 'Change House/Pen',
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.sm,
                    onPressed: () => _edit(() => _allocPhase = 'pens'),
                  ),
                  const Text('A suggestion — every number stays editable.', style: TextStyle(fontSize: 12, color: _slate500)),
                ]),
              ),
            ]),
          ),
          const _InfoBox(
            strong: 'Complete flock information now.',
            text: ' Only the essential fields are required to continue. You can fill in the rest later, but entering it now '
                'gives you a complete flock history from the beginning.',
          ),
          if (existingFlocks.isNotEmpty) ...[
            AppCheckbox(
              value: _showExistingFlocks,
              onChanged: (v) => setState(() => _showExistingFlocks = v),
              label: 'Show existing flock assignments (${existingFlocks.length})',
            ),
            if (_showExistingFlocks)
              Container(
                decoration: BoxDecoration(color: _slate50, border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final f in existingFlocks)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _slate200))),
                      child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(f.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                        const _Badge('Existing', _slate200, _slate700, filled: true),
                        Text('${f.houseName ?? 'No pen'} · ${fmtInt(f.quantity)} birds',
                            style: const TextStyle(fontSize: 13, color: _slate600)),
                      ]),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Wrap(children: [
                      const Text('Shown for context. Change these on the ', style: TextStyle(fontSize: 12, color: _slate500)),
                      InkWell(
                        onTap: () => _openLink('Flock Groups', '/flocks', 'flocks'),
                        child: const Text('Flock Groups', style: TextStyle(fontSize: 12, color: _blue600)),
                      ),
                      const Text(' page.', style: TextStyle(fontSize: 12, color: _slate500)),
                    ]),
                  ),
                ]),
              ),
          ],
          for (final x in activeFlocks) _flockCard(fe, x.row, x.index, houseViews),
          if (nextBatch != null)
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                label: 'Next batch: ${nextBatch.batch.batchCode.isNotEmpty ? nextBatch.batch.batchCode : nextBatch.batch.batchName}',
                icon: Icons.arrow_forward,
                variant: AppButtonVariant.outline,
                onPressed: () => _chooseBatch(nextBatch.batch.key),
              ),
            ),
        ],
      ],
    );
  }

  Widget _batchSummary(
    BatchAllocationView a,
    int chosen,
    List<HouseRowView> houseViews,
    List<HouseRowView> allocatable,
    Set<String> pensIn,
  ) {
    final label = a.batch.batchCode.isNotEmpty ? a.batch.batchCode : 'this batch';
    Widget update() => InkWell(
          onTap: () => _fixBatchSize(a.batch.key),
          child: Text('Update $label', style: const TextStyle(fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _slate50, border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          '${a.batch.batchCode.isNotEmpty ? a.batch.batchCode : a.batch.batchName}${a.batch.breed.isNotEmpty ? ' · ${a.batch.breed}' : ''}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        if (a.mustBeFullyAllocated)
          const Text('Birds you already had — every one of them needs a pen', style: TextStyle(fontSize: 12, color: _slate600)),
        const SizedBox(height: 8),
        _grid([
          _Figure('Original birds', a.batchBirds),
          _Figure('Already allocated', a.previouslyAllocated),
          _Figure('This allocation', a.thisAllocation, color: _blue700),
          _Figure(
            a.status == 'over' ? 'Over by' : 'Remaining',
            a.status == 'over' ? a.overBy : a.remaining,
            color: a.status == 'over' ? _red700 : a.remaining > 0 ? _amber700 : _emerald700,
          ),
        ]),
        if (_allocPhase == 'pens') ...[
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                color: _blue600,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(children: [
                  const Expanded(
                    child: Text('Choose Houses/Pens', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                  Text('$chosen selected', style: const TextStyle(color: Colors.white, fontSize: 13)),
                ]),
              ),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    AppButton(label: 'Select all', variant: AppButtonVariant.outline, size: AppButtonSize.sm, onPressed: () => _selectAllPens(true)),
                    AppButton(
                      label: 'Clear',
                      variant: AppButtonVariant.outline,
                      size: AppButtonSize.sm,
                      onPressed: chosen == 0 ? null : () => _selectAllPens(false),
                    ),
                    AppButton(label: 'New pen', icon: Icons.add, variant: AppButtonVariant.outline, size: AppButtonSize.sm, onPressed: _newPen),
                  ]),
                  const SizedBox(height: 10),
                  _grid([
                    for (final v in houseViews)
                      () {
                        final on = pensIn.contains(v.row.key);
                        final full = !v.hasRoom;
                        final locked = full && !on;
                        final free = v.load?.capacity == null ? null : (v.load!.capacity! - v.load!.occupied).clamp(0, 1 << 31);
                        return InkWell(
                          onTap: locked ? null : () => _togglePen(v.row.key, !on),
                          borderRadius: BorderRadius.circular(8),
                          child: Tooltip(
                            message: locked ? 'This pen is full' : '',
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
                              decoration: BoxDecoration(
                                color: on ? _blue50 : locked ? _slate100 : Colors.white,
                                border: Border.all(color: on ? _blue400 : _slate200),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                SizedBox(
                                  width: 30,
                                  height: 24,
                                  child: Checkbox(
                                    value: on,
                                    visualDensity: VisualDensity.compact,
                                    onChanged: locked ? null : (c) => _togglePen(v.row.key, c == true),
                                  ),
                                ),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                      Text(v.row.houseName.isEmpty ? '(unnamed)' : v.row.houseName,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontWeight: FontWeight.w500, color: locked ? _slate500 : _slate900)),
                                      if (full) const _Badge('Full', _red300, _red700),
                                    ]),
                                    Text(
                                      full && v.load?.capacity != null
                                          ? '${fmtInt(v.load!.total)} of ${fmtInt(v.load!.capacity!)} birds'
                                          : free == null
                                              ? 'No limit set'
                                              : '${fmtInt(free)} free',
                                      style: const TextStyle(fontSize: 12, color: _slate500),
                                    ),
                                  ]),
                                ),
                              ]),
                            ),
                          ),
                        );
                      }(),
                  ]),
                  if (allocatable.isEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: _amber50, border: Border.all(color: _amber200), borderRadius: BorderRadius.circular(8)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.warning_amber_rounded, size: 16, color: _amber900),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _draft.houses.isEmpty
                                  ? 'You have no houses or pens yet, so there is nowhere to put these birds.'
                                  : 'Every pen you have is full, so there is nowhere to put these birds.',
                              style: const TextStyle(fontSize: 13, color: _amber900),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: _amber600, visualDensity: VisualDensity.compact),
                            onPressed: _newPen,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Create a pen'),
                          ),
                          if (_draft.houses.isNotEmpty)
                            const Text("— or raise a pen's capacity from the note on any row once it is placed.",
                                style: TextStyle(fontSize: 12, color: _amber800)),
                        ]),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: _blue600),
                      onPressed: chosen == 0 ? null : () => _edit(() => _allocPhase = 'allocate'),
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: const Text('Continue to allocation'),
                    ),
                    Text(
                      chosen == 0 ? 'Tick the pens these birds are in.' : '$chosen pen${chosen == 1 ? '' : 's'} chosen.',
                      style: const TextStyle(fontSize: 12, color: _slate500),
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
        ],
        if (a.status == 'over') ...[
          const SizedBox(height: 8),
          DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 13, color: _red700),
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('This allocation is ${fmtInt(a.overBy)} birds more than ${a.batch.batchCode.isNotEmpty ? a.batch.batchCode : 'the batch'} has. '
                  'Lower a pen, or raise the batch. '),
              update(),
            ]),
          ),
        ],
        if (a.status == 'partial' && a.remaining > 0) ...[
          const SizedBox(height: 8),
          DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 13, color: _amber700),
            child: a.mustBeFullyAllocated
                ? Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('${fmtInt(a.remaining)} birds still need a pen — these are birds you already had, so all of them must be '
                        'somewhere. Put them in a pen, or correct the batch. '),
                    update(),
                  ])
                : Text('${fmtInt(a.remaining)} birds will stay unallocated — you can place them later.'),
          ),
        ],
        if (a.status == 'complete') ...[
          const SizedBox(height: 8),
          const Row(children: [
            Icon(Icons.check_circle_outline, size: 16, color: _emerald700),
            SizedBox(width: 6),
            Text('Fully allocated.', style: TextStyle(fontSize: 13, color: _emerald700)),
          ]),
        ],
      ]),
    );
  }

  Widget _flockCard(Map<String, Map<int, Map<String, String>>> fe, FlockRow f, int i, List<HouseRowView> houseViews) {
    final id = 'f.${f.key}';
    final reduction = historicalReduction(f);
    final penLoad = f.houseKey.isEmpty ? null : houseLoad(f.houseKey, _draft, _ctx);
    final noteText = penLoad == null ? null : houseCapacityNote(penLoad);
    String? penHint;
    if (penLoad != null) {
      final parts = <String>[
        if (penLoad.activeFlocks > 0)
          'Already holds ${fmtInt(penLoad.occupied)} in ${penLoad.activeFlocks} flock${penLoad.activeFlocks == 1 ? '' : 's'} — this adds another',
        if (penLoad.capacity != null && noteText == null)
          '${fmtInt((penLoad.capacity! - penLoad.total).clamp(0, 1 << 31))} of ${fmtInt(penLoad.capacity!)} still free',
      ];
      penHint = parts.isEmpty ? null : parts.join(' · ');
    }
    final batch = _draft.batches.where((x) => x.key == f.batchKey).firstOrNull;
    return _RowCard(
      index: i,
      invalid: _rowInvalid(fe, 'flocks', i),
      header: _RowHeader(
        label: f.name.isEmpty ? 'Flock ${i + 1}' : f.name,
        badge: reduction > 0 ? _Badge('−${fmtInt(reduction)}', _amber300, _amber700) : const _Badge('Balanced', _slate200, _slate500),
        onRemove: () => _removeFlock(i),
      ),
      children: [
        _Field(
          label: 'House/Pen *',
          error: _errorFor(fe, 'flocks', i, 'houseKey'),
          hint: penHint,
          note: noteText == null
              ? null
              : Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('$noteText ', style: const TextStyle(fontSize: 12, color: _amber700)),
                  InkWell(
                    onTap: () => _fixCapacity(f.houseKey),
                    child: Text('Update ${penLoad?.label.isNotEmpty == true ? penLoad!.label : 'this pen'}',
                        style: const TextStyle(
                            fontSize: 12, color: _amber700, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
                  ),
                ]),
          child: AppSelect<String>(
            value: f.houseKey.isEmpty ? null : f.houseKey,
            hintText: 'House',
            items: [
              for (final v in penOptions(houseViews, f.houseKey))
                AppSelectItem(value: v.row.key, label: v.row.houseName.isEmpty ? '(unnamed)' : v.row.houseName),
            ],
            onChanged: (v) {
              if (v == null) return;
              final from = _draft.houses.where((h) => h.key == f.houseKey).firstOrNull;
              final to = _draft.houses.where((h) => h.key == v).firstOrNull;
              _edit(() {
                f.name = renameForHouse(f.name, batch?.batchCode ?? '', from?.houseName ?? '', to?.houseName ?? '');
                f.houseKey = v;
                if (f.startDate.isEmpty) f.startDate = batch?.startDate ?? '';
              });
            },
          ),
        ),
        _Field(
          label: 'Flock Name *',
          error: _errorFor(fe, 'flocks', i, 'name'),
          child: _text('$id.name', f.name, (s) => _edit(() => f.name = s), hint: 'B1 - Pen 1'),
        ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _Field(
              label: 'Originally Placed *',
              error: _errorFor(fe, 'flocks', i, 'originallyPlaced'),
              child: _number('$id.placed', f.originallyPlaced, (s) => _edit(() => f.originallyPlaced = s), hint: '1000'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Field(
              label: 'Current Live Birds *',
              error: _errorFor(fe, 'flocks', i, 'currentLiveBirds'),
              child: _number('$id.live', f.currentLiveBirds, (s) => _edit(() => f.currentLiveBirds = s), hint: '919'),
            ),
          ),
        ]),
        const Divider(height: 8, color: _slate100),
        _Field(
          label: 'Breed',
          hint: "Blank takes the batch's breed",
          child: BreedPicker(
            value: f.breed,
            known: _knownBreeds,
            hintText: (batch?.breed ?? '').isNotEmpty ? batch!.breed : 'Same as the batch',
            onChanged: (b) => _edit(() => f.breed = b),
          ),
        ),
        _Field(
          label: 'Notes',
          child: _text('$id.notes', f.notes ?? '', (s) => _edit(() => f.notes = s),
              hint: 'Anything worth remembering about this flock'),
        ),
        if (!(batch?.isHistorical ?? true))
          _Field(
            label: 'Have the birds arrived?',
            child: AppCheckbox(
              value: f.hasArrived,
              onChanged: (v) => _edit(() => f.hasArrived = v),
              label: 'Yes, they are in the pen',
            ),
          ),
        const Divider(height: 8, color: _slate100),
        _Field(
          label: 'How do you know its age?',
          child: AppSelect<String>(
            value: f.ageMode,
            items: const [
              AppSelectItem(value: 'date', label: 'I know the placement/start date'),
              AppSelectItem(value: 'age', label: 'I know the current age'),
            ],
            onChanged: (v) => _edit(() => f.ageMode = v ?? 'date'),
          ),
        ),
        if (f.ageMode == 'date')
          _Field(
            label: 'Placement date',
            error: _errorFor(fe, 'flocks', i, 'startDate'),
            child: _date(f.startDate, (s) => _edit(() => f.startDate = s)),
          )
        else
          _Field(
            label: 'Current age (weeks)',
            error: _errorFor(fe, 'flocks', i, 'currentAgeInWeeks'),
            hint: "We'll work back from today and record the date as estimated.",
            child: _number('$id.age', f.currentAgeInWeeks, (s) => _edit(() => f.currentAgeInWeeks = s), hint: '70'),
          ),
      ],
    );
  }

  // ---------------------------------------------------------- step 3

  Widget _reconcileStep() {
    final needs = flocksNeedingReconciliation(_draft.flocks);
    return _Section(
      icon: Icons.assignment_outlined,
      title: 'What happened to the missing birds?',
      description:
          'We have assumed the missing birds died — change any flock where that is wrong. These losses happened before tracking began, so they are recorded as an opening position and never appear as today’s deaths.',
      children: [
        if (needs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Column(children: [
              Icon(Icons.check_circle_outline, size: 40, color: _emerald600),
              SizedBox(height: 6),
              Text('Every flock balances. No reconciliation needed.', style: TextStyle(color: _slate700)),
            ]),
          ),
        for (final (i, f) in _draft.flocks.indexed)
          if (historicalReduction(f) > 0)
            () {
              final b = breakdown(f);
              final id = 'r.${f.key}';
              Widget bucket(String label, String field, String value, {String? hint}) => _Field(
                    label: label,
                    hint: hint,
                    child: _number('$id.$field', value, (s) => _edit(() => balanceBreakdown(f, field, s))),
                  );
              return _Striped(
                index: i,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(f.name.isEmpty ? '(unnamed flock)' : f.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                        Text('${fmtInt(count(f.originallyPlaced))} placed → ${fmtInt(count(f.currentLiveBirds))} standing today',
                            style: const TextStyle(fontSize: 13, color: _slate600)),
                      ]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(10)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        const Text('REMAINING TO ACCOUNT',
                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500, letterSpacing: .5, color: _slate500)),
                        Text(fmtInt(b.difference), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _amber600)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  AppCheckbox(
                    value: !f.historyKnown,
                    onChanged: (v) => _edit(() {
                      f.historyKnown = !v;
                      f.reconciliationTouched = true;
                      // "I don't know" clears the pre-filled figures.
                      if (v) {
                        f.historicalMortality = '';
                        f.historicalSold = '';
                        f.historicalCulled = '';
                        f.historicalTransferred = '';
                      }
                    }),
                    label: "I don't know the historical breakdown",
                  ),
                  if (f.historyKnown) ...[
                    const SizedBox(height: 6),
                    _grid([
                      bucket('Known mortality', 'historicalMortality', f.historicalMortality, hint: 'Takes whatever the others do not'),
                      bucket('Sold', 'historicalSold', f.historicalSold),
                      bucket('Culled', 'historicalCulled', f.historicalCulled),
                      bucket('Transferred out', 'historicalTransferred', f.historicalTransferred),
                      _Field(label: 'Other / unknown', child: _ReadOnlyBox(fmtInt(b.other))),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      b.overStated
                          ? 'The breakdown adds up to ${fmtInt(b.stated)} but only ${fmtInt(b.difference)} birds remain to account for.'
                          : '${fmtInt(b.stated)} of ${fmtInt(b.difference)} accounted for; the remaining ${fmtInt(b.other)} is recorded as unknown, not as mortality.',
                      style: TextStyle(fontSize: 12, color: b.overStated ? _red600 : _slate500),
                    ),
                  ] else
                    Text.rich(TextSpan(style: const TextStyle(fontSize: 12, color: _slate500), children: [
                      TextSpan(text: 'All ${fmtInt(b.difference)} will be recorded as an '),
                      const TextSpan(text: 'opening bird adjustment', style: TextStyle(fontWeight: FontWeight.w700)),
                      const TextSpan(text: ' — not as mortality, and not as a sale.'),
                    ])),
                ]),
              );
            }(),
      ],
    );
  }

  // ---------------------------------------------------------- step 4

  Widget _reviewStep(({List<SetupRowError> errors, List<SetupRowError> warnings}) v, SetupTotals t) {
    final views = batchAllocationViews(_draft, _ctx);
    final reused = (h: _draft.houses.where((h) => h.existingHouseId != null).length, b: _draft.batches.where((b) => b.existingBatchId != null).length);
    String money(String raw) {
      final n = double.tryParse(raw.trim());
      return raw.trim().isEmpty || n == null ? '' : _money2(n);
    }

    Widget problems(List<SetupRowError> list, Color bg, Color border, Color ink, IconData icon) => Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final e in list)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 15, color: ink)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Builder(builder: (_) {
                      final fix = _fixFor(e);
                      return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text('${e.message} ', style: TextStyle(fontSize: 13, color: ink)),
                        if (fix != null)
                          InkWell(
                            onTap: fix.onTap,
                            child: Text(fix.label,
                                style: TextStyle(
                                    fontSize: 13, color: ink, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
                          ),
                      ]);
                    }),
                  ),
                ]),
              ),
          ]),
        );

    return _Section(
      icon: Icons.check_circle_outline,
      title: 'Farm setup summary',
      description: 'Nothing has been saved yet. Check the numbers, then create your farm.',
      children: [
        _grid([
          _Stat('Batches', t.batchCount, tone: 'blue'),
          _Stat('Original batch birds', t.batchBirds, tone: 'blue'),
          _Stat('Houses/pens', t.houseCount, tone: 'violet'),
          _Stat('Current flocks', t.flockCount, tone: 'violet'),
          _Stat('Birds originally placed', t.originallyPlaced),
          _Stat('Current live birds', t.openingLiveBirds, tone: 'emerald'),
          _Stat('Historical reduction', t.historicalReduction, tone: 'amber'),
          _Stat('Flocks with unknown history', t.flocksWithUnknownHistory, tone: 'rose'),
        ]),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Historical reduction, broken down', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            _grid([
              _Stat('Known mortality', t.historicalMortality, tone: 'rose', small: true),
              _Stat('Sold', t.historicalSold, tone: 'blue', small: true),
              _Stat('Culled', t.historicalCulled, tone: 'violet', small: true),
              _Stat('Transferred', t.historicalTransferred, tone: 'slate', small: true),
              _Stat('Other / unknown', t.otherAdjustment, tone: 'amber', small: true),
            ]),
            const SizedBox(height: 6),
            Text(
              "None of this is a production record. It establishes what was true on ${_ctx.businessDate} — your company's business date — and nothing more.",
              style: const TextStyle(fontSize: 12, color: _slate500),
            ),
          ]),
        ),
        for (final (title, existing, created) in [
          ('Houses/pens', reused.h, _draft.houses.length - reused.h),
          ('Batches', reused.b, _draft.batches.length - reused.b),
        ])
          AppCard(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text.rich(TextSpan(style: const TextStyle(fontSize: 13, color: _slate600), children: [
                TextSpan(text: '${fmtInt(existing)} existing, reused · '),
                TextSpan(text: '${fmtInt(created)} to create', style: const TextStyle(fontWeight: FontWeight.w500, color: _blue700)),
              ])),
            ]),
          ),
        for (final bv in views)
          if (bv.thisAllocation > 0 || _draft.flocks.any((f) => f.batchKey == bv.batch.key)) _reviewBatch(bv, money),
        if (v.warnings.isNotEmpty) problems(v.warnings, _amber50, _amber200, _amber800, Icons.warning_amber_rounded),
        if (v.errors.isNotEmpty) problems(v.errors, _red50, _red200, _red700, Icons.error_outline),
      ],
    );
  }

  Widget _reviewBatch(BatchAllocationView v, String Function(String) money) {
    final bt = v.batch;
    final open = _openReviewBatches.contains(bt.key);
    final flocks = [for (final f in _draft.flocks) if (f.batchKey == bt.key) f];
    final cpc = double.tryParse(bt.costPerChick.trim()) ?? 0;
    final birds = double.tryParse(bt.numberOfBirds.trim()) ?? 0;
    final totalTyped = double.tryParse(bt.totalCost.trim()) ?? 0;
    final total = totalTyped != 0 ? totalTyped : cpc * birds;
    final paid = double.tryParse(bt.amountPaid.trim()) ?? 0;
    final supplier = _suppliers.where((s) => s['supplierId'] == bt.supplierId).firstOrNull;
    final account = _cashAccounts.where((a) => a['poultryCashAccountId'] == bt.poultryCashAccountId).firstOrNull;
    return Container(
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => open ? _openReviewBatches.remove(bt.key) : _openReviewBatches.add(bt.key)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Icon(open ? Icons.expand_more : Icons.chevron_right, size: 18, color: _slate500),
                Text(bt.batchCode.isNotEmpty ? bt.batchCode : bt.batchName, style: const TextStyle(fontWeight: FontWeight.w500)),
                _StatusBadge(v.status),
                if (bt.existingBatchId == null && !bt.isHistorical) const _Badge('New purchase', _blue300, _blue700),
                Text(open ? 'Hide details' : 'View details', style: const TextStyle(fontSize: 12, color: _blue600)),
              ]),
              const SizedBox(height: 2),
              Text(
                'original ${fmtInt(v.batchBirds)} · already ${fmtInt(v.previouslyAllocated)} · this ${fmtInt(v.thisAllocation)} · remaining ${fmtInt(v.remaining)}',
                style: const TextStyle(fontSize: 12, color: _slate600),
              ),
            ]),
          ),
        ),
        if (open)
          Container(
            color: _slate50,
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const _SectionLabel('Batch details'),
              const SizedBox(height: 6),
              _grid([
                _Detail('Batch name', bt.batchName),
                _Detail('Batch code', bt.batchCode),
                _Detail('Breed', bt.breed),
                _Detail('Number of birds', fmtInt(v.batchBirds)),
                _Detail('Start date', bt.startDate),
                _Detail('Source',
                    bt.existingBatchId != null ? 'Existing batch (reused)' : bt.isHistorical ? 'Already had these birds' : 'Buying these birds now'),
                _Detail('Supplier', supplier == null ? null : '${supplier['name'] ?? ''}'),
                _Detail('Supplier type', bt.supplierType == 'foreign' ? 'Foreign' : bt.supplierType.isNotEmpty ? 'Local' : ''),
                _Detail('Cost per chick', money(bt.costPerChick)),
                _Detail('Total cost', total > 0 ? _money2(total) : ''),
                _Detail('Amount paid', money(bt.amountPaid)),
                _Detail('Balance owed', total > 0 ? _money2((total - paid).clamp(0, double.infinity)) : ''),
                _Detail(bt.isHistorical ? 'Paid from cash account' : 'Pay from cash account',
                    account == null ? null : '${account['accountName'] ?? ''}'),
                if (bt.supplierType == 'foreign') _Detail('Dollar rate', bt.dollarConversionRate),
                _Detail('Order placed', bt.orderPlacementDate),
                _Detail('Estimated arrival', bt.estimatedArrivalDate),
                if ((bt.notes ?? '').isNotEmpty) _Detail('Notes', bt.notes),
              ]),
            ]),
          ),
        Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: _slate100))),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
          child: Text('FLOCKS IN THIS BATCH (${flocks.length})',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: .5, color: _slate500)),
        ),
        for (final f in flocks)
          () {
            final house = _draft.houses.where((h) => h.key == f.houseKey).firstOrNull;
            final b = breakdown(f);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _slate100))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  const Icon(Icons.egg_outlined, size: 16, color: Color(0xFF7C3AED)),
                  const Text('Flock', style: TextStyle(fontSize: 12, color: _slate500)),
                  Text(f.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                ]),
                Text.rich(TextSpan(style: const TextStyle(fontSize: 13, color: _slate600), children: [
                  TextSpan(
                      text: '${house?.houseName ?? ''} · placed ${fmtInt(count(f.originallyPlaced))} · current ${fmtInt(count(f.currentLiveBirds))}'),
                  if (b.difference > 0)
                    TextSpan(text: ' · opening reduction ${fmtInt(b.difference)}', style: const TextStyle(color: _amber700)),
                ])),
                if (open) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0x66F5F3FF),
                      border: Border.all(color: const Color(0xFFEDE9FE)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: _grid([
                      _Detail('Flock name', f.name),
                      _Detail('House/Pen', house?.houseName),
                      _Detail('Breed', f.breed.isNotEmpty ? f.breed : bt.breed.isNotEmpty ? '${bt.breed} (batch)' : ''),
                      _Detail('Originally placed', fmtInt(count(f.originallyPlaced))),
                      _Detail('Current live birds', fmtInt(count(f.currentLiveBirds))),
                      _Detail('Opening reduction', fmtInt(b.difference)),
                      if (f.ageMode == 'age')
                        _Detail('Current age', f.currentAgeInWeeks.isNotEmpty ? '${f.currentAgeInWeeks} weeks (date estimated)' : '')
                      else
                        _Detail('Placement date', f.startDate),
                      if (!bt.isHistorical) _Detail('Birds arrived', f.hasArrived ? 'Yes' : 'Not yet'),
                      if (b.difference > 0) ...[
                        _Detail('Known mortality', fmtInt(b.mortality)),
                        _Detail('Sold', fmtInt(b.sold)),
                        _Detail('Culled', fmtInt(b.culled)),
                        _Detail('Transferred', fmtInt(b.transferred)),
                        _Detail('Other / unknown', fmtInt(b.other)),
                        _Detail('History', f.historyKnown ? 'Known' : 'Unknown'),
                      ],
                      if ((f.notes ?? '').isNotEmpty) _Detail('Notes', f.notes),
                    ]),
                  ),
                ],
              ]),
            );
          }(),
      ]),
    );
  }

  // ------------------------------------------------------------- inputs

  Widget _text(String id, String value, ValueChanged<String> onChanged, {String? hint, bool enabled = true}) =>
      AppInput(key: ValueKey(id), controller: _ctl(id, value), hintText: hint, enabled: enabled, onChanged: onChanged);

  Widget _number(String id, String value, ValueChanged<String> onChanged,
          {String? hint, bool enabled = true, bool decimal = false}) =>
      AppNumberInput(
        key: ValueKey(id),
        controller: _ctl(id, value),
        hintText: hint ?? '0',
        enabled: enabled,
        allowDecimal: decimal,
        onChanged: onChanged,
      );

  Widget _date(String value, ValueChanged<String> onChanged, {bool enabled = true}) => AppDateField(
        value: businessDateAsDateTime(value),
        enabled: enabled,
        onChanged: (d) => onChanged(d == null ? '' : isoDay(d)),
      );
}

/// "1,234.50": toLocaleString with exactly two decimals.
String _money2(num n) => ghc(n).replaceFirst('GHC ', '');

/// Two columns of whatever fits, as the web's `grid-cols-2`.
Widget _grid(List<Widget> children) => LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 8) / 2;
      return Wrap(spacing: 8, runSpacing: 8, children: [for (final x in children) SizedBox(width: w, child: x)]);
    });

// ---------------------------------------------------------------- pieces

/// A step's container: a card with the step icon, title and description.
class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.description, required this.children});
  final IconData icon;
  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: const Color(0x99F8FAFC),
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: _blue50, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 18, color: _blue600),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(description, style: const TextStyle(fontSize: 13, color: _slate600, height: 1.4)),
                ]),
              ),
            ]),
          ),
          const Divider(height: 1, color: _slate100),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(height: 12), c],
            ]),
          ),
        ]),
      );
}

/// The slate generator strip above a grid.
class _GeneratorBox extends StatelessWidget {
  const _GeneratorBox({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: _slate50, border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(height: 10), c],
        ]),
      );
}

/// A row's shell: red when invalid, otherwise alternating blue / white.
class _RowCard extends StatelessWidget {
  const _RowCard({required this.index, required this.invalid, required this.header, required this.children});
  final int index;
  final bool invalid;
  final Widget header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final (bg, border, left) = invalid
        ? (_red50, _red300, _red500)
        : index.isEven
            ? (_blue200, _blue300, _blue600)
            : (Colors.white, _slate200, _slate300);
    return Container(
      decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      // The left stripe overlays the edge, so the card never has to measure
      // its own height (the two-column grids inside cannot report one).
      child: Stack(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
          child: Theme(
            data: Theme.of(context).copyWith(
              inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(filled: true, fillColor: Colors.white),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              header,
              for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(height: 10), c],
            ]),
          ),
        ),
        Positioned(left: 0, top: 0, bottom: 0, width: 4, child: ColoredBox(color: left)),
      ]),
    );
  }
}

/// The reconciliation card stripe.
class _Striped extends StatelessWidget {
  const _Striped({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => _RowCard(index: index, invalid: false, header: const SizedBox.shrink(), children: [child]);
}

class _RowHeader extends StatelessWidget {
  const _RowHeader({
    required this.label,
    required this.badge,
    this.onRemove,
    this.removeLabel = 'Remove',
  });
  final String label;
  final Widget badge;
  final VoidCallback? onRemove;
  final String removeLabel;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.only(bottom: 6),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _slate100))),
        child: Row(children: [
          Expanded(
            child: Text(label.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: .5, color: _slate500)),
          ),
          badge,
          if (onRemove != null)
            IconButton(
              tooltip: removeLabel,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, size: 18, color: _red600),
              onPressed: onRemove,
            ),
        ]),
      );
}

class _Field extends StatelessWidget {
  const _Field({this.label, this.error, this.hint, this.note, required this.child});
  final String? label;
  final String? error;
  final String? hint;

  /// Amber: worth acting on, never blocking.
  final Widget? note;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(label!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        child,
        if (hint != null && error == null)
          Padding(padding: const EdgeInsets.only(top: 3), child: Text(hint!, style: const TextStyle(fontSize: 12, color: _slate500))),
        if (note != null && error == null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.warning_amber_rounded, size: 13, color: _amber700)),
              const SizedBox(width: 4),
              Expanded(child: note!),
            ]),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.error_outline, size: 13, color: _red600)),
              const SizedBox(width: 4),
              Expanded(child: Text(error!, style: const TextStyle(fontSize: 12, color: _red600))),
            ]),
          ),
      ]);
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.border, this.color, {this.filled = false});
  final String label;
  final Color border;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: filled ? border : null,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: color)),
      );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.status);
  final String status;

  @override
  Widget build(BuildContext context) => switch (status) {
        'over' => const _Badge('Over', _red300, _red700),
        'unallocated' => const _Badge('New', _blue300, _blue700),
        'partial' => const _Badge('Partial', _amber300, _amber700),
        _ => const _Badge('Done', _emerald200, _emerald700),
      };
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.suffix});
  final String text;
  final String? suffix;

  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(
        text: text.toUpperCase(),
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: .5, color: _slate500),
        children: [if (suffix != null) TextSpan(text: suffix, style: const TextStyle(fontWeight: FontWeight.w400, color: _slate400))],
      ));
}

class _RadioRow extends StatelessWidget {
  const _RadioRow({required this.checked, required this.onSelect, required this.title, required this.detail});
  final bool checked;
  final VoidCallback onSelect;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: checked ? _blue50 : Colors.white,
            border: Border.all(color: checked ? _blue400 : _slate200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              margin: const EdgeInsets.only(top: 2),
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: checked ? _blue600 : _slate300, width: 2)),
              child: checked
                  ? Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: _blue600))
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                Text(detail, style: const TextStyle(fontSize: 12, color: _slate600, height: 1.35)),
              ]),
            ),
          ]),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: on,
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: on ? _indigo600 : Colors.white,
              border: Border.all(color: on ? _indigo600 : _slate300),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: on ? Colors.white : _slate700)),
          ),
        ),
      );
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.strong, required this.text});
  final String strong;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: _blue50, border: Border.all(color: _blue200), borderRadius: BorderRadius.circular(8)),
        child: Text.rich(TextSpan(style: const TextStyle(fontSize: 13, color: _blue900), children: [
          TextSpan(text: strong, style: const TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: text),
        ])),
      );
}

class _BluePanel extends StatelessWidget {
  const _BluePanel({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: _slate50, border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: _blue600,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Padding(padding: const EdgeInsets.all(12), child: child),
        ]),
      );
}

class _ReadOnlyBox extends StatelessWidget {
  const _ReadOnlyBox(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 40),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: _slate100, border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(fontSize: 14, color: _slate700)),
      );
}

/// One number with its label (the allocation header is four of these).
class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, {this.color});
  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: _slate500)),
          Text(fmtInt(value), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: color ?? _slate900)),
        ]),
      );
}

/// The tile /production-records uses: white card, coloured number.
class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.tone = 'slate', this.small = false});
  final String label;
  final int value;
  final String tone;
  final bool small;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.all(small ? 10 : 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _slate200),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, letterSpacing: .5, color: _slate500)),
          const SizedBox(height: 2),
          Text(fmtInt(value), style: TextStyle(fontSize: small ? 17 : 19, fontWeight: FontWeight.w700, color: _tones[tone])),
        ]),
      );
}

/// One read-only fact on Review. Blank reads "—".
class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: _slate500)),
        Text((value ?? '').trim().isEmpty ? '—' : value!, style: const TextStyle(fontWeight: FontWeight.w500)),
      ]);
}
