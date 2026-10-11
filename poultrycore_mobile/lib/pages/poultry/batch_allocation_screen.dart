import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/form_section.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import 'bulk_house_screen.dart';

/// Flock Groups → "Add Multiple Flocks", as the web's
/// `components/poultry/batch-allocation-dialog.tsx` with the arithmetic of
/// `lib/flocks/allocation.ts`: pick a batch, tick the houses/pens, set how
/// many birds go into each, review, and create every flock in one
/// `POST /api/Flock/bulk-allocate`. The server re-runs every rule under a
/// lock on the batch, so either every flock exists afterwards or none does.
///
/// Pops with true when flocks were created.
class BatchAllocationScreen extends StatefulWidget {
  const BatchAllocationScreen({
    super.key,
    required this.session,
    required this.company,
    this.flocks = const [],
    this.source = 'Flock Groups page',
    this.batchId,
  });

  /// The web dialog's `batchId`: opens straight on that batch's allocation.
  final int? batchId;

  final Session session;
  final Company company;

  /// The flocks the host page already holds. What each batch still has to
  /// place is its size minus these, as the web works it out — so the list
  /// cannot offer a batch the server would then refuse.
  final List<Map<String, dynamic>> flocks;
  final String source;

  @override
  State<BatchAllocationScreen> createState() => _BatchAllocationScreenState();
}

class AllocatableBatch {
  const AllocatableBatch({
    required this.batchId,
    required this.batchCode,
    required this.batchName,
    required this.numberOfBirds,
    required this.unallocatedBirds,
  });
  final int batchId;
  final String batchCode;
  final String batchName;
  final int numberOfBirds;
  final int unallocatedBirds;
}

enum _Step { batch, allocate, review, done }

const _maxRows = 200;
const _maxName = 100;

class _House {
  const _House(this.id, this.name, this.capacity, this.occupied);
  final int id;
  final String name;
  final int? capacity;
  final int occupied;

  /// availableCapacity: null when no capacity is set.
  int? get room => (capacity ?? 0) <= 0 ? null : (capacity! - occupied).clamp(0, capacity!);
}

class _Row {
  _Row(this.houseId, String name)
      : name = TextEditingController(text: name),
        quantity = TextEditingController();
  final int houseId;
  final TextEditingController name;
  final TextEditingController quantity;
  void dispose() {
    name.dispose();
    quantity.dispose();
  }
}

String _dupKey(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// parseQuantity: blank = 0, null = not a whole number.
int? _qty(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return 0;
  return RegExp(r'^\d+$').hasMatch(t) ? int.tryParse(t) : null;
}

String _n(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

class _BatchAllocationScreenState extends State<BatchAllocationScreen> {
  _Step _step = _Step.batch;

  /// Null while loading.
  List<AllocatableBatch>? _batches;

  @override
  void initState() {
    super.initState();
    _loadBatches();
    final id = widget.batchId;
    if (id != null && id > 0) {
      _step = _Step.allocate;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadContext(id);
      });
    }
  }

  Future<void> _loadBatches() async {
    try {
      final res = await widget.session.farmClient.get('/api/MainFlockBatch', query: {
        'userId': widget.session.tokens.userId ?? '',
        'farmId': widget.company.farmId,
      });
      final list = res is List ? res : (res is Map && res['data'] is List ? res['data'] as List : const []);
      final used = <int, int>{};
      for (final f in widget.flocks) {
        final id = _int(f['batchId']);
        if (id > 0) used[id] = (used[id] ?? 0) + _int(f['quantity']);
      }
      if (!mounted) return;
      setState(() => _batches = [
            for (final b in list)
              if (b is Map && _int(b['batchId']) > 0)
                AllocatableBatch(
                  batchId: _int(b['batchId']),
                  batchCode: '${b['batchCode'] ?? ''}',
                  batchName: '${b['batchName'] ?? ''}',
                  numberOfBirds: _int(b['numberOfBirds']),
                  unallocatedBirds:
                      (_int(b['numberOfBirds']) - (used[_int(b['batchId'])] ?? 0)).clamp(0, 1 << 31),
                ),
          ]);
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (_) {
      if (mounted) setState(() => _loadError = 'Could not load batches.');
    }
  }

  bool _loading = false;
  String? _loadError;

  // allocation-context
  int? _batchId;
  String _batchCode = '';
  String _batchName = '';
  String _breed = '';
  String _startDate = '';
  int _original = 0;
  int _allocated = 0;
  int _available = 0;
  List<_House> _houses = const [];
  List<String> _existingNames = const [];

  final List<_Row> _rows = [];
  bool _submitted = false;
  bool _saving = false;
  String _note = '';
  Map<int, Map<String, String>> _serverErrors = {};

  // result
  int _createdCount = 0;
  int _birdsAllocated = 0;
  int _remainingAfter = 0;

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  static int _int(Object? v) => int.tryParse('${v ?? ''}') ?? 0;

  Future<void> _loadContext(int batchId) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final res = await widget.session.farmClient.get(
        '/api/Flock/allocation-context/$batchId',
        query: {
          'userId': widget.session.tokens.userId ?? '',
          'farmId': widget.company.farmId,
        },
      );
      if (!mounted) return;
      final m = res is Map ? res : const {};
      final b = m['batch'] is Map ? m['batch'] as Map : const {};
      setState(() {
        _batchId = batchId;
        _batchCode = '${b['batchCode'] ?? ''}';
        _batchName = '${b['batchName'] ?? ''}';
        _breed = '${b['breed'] ?? ''}';
        _startDate = '${b['startDate'] ?? ''}'.split('T').first;
        _original = _int(b['originalBirds']);
        _allocated = _int(b['allocatedBirds']);
        _available = _int(b['unallocatedBirds']);
        _houses = [
          for (final h in (m['houses'] is List ? m['houses'] as List : const []))
            if (h is Map)
              _House(
                _int(h['houseId']),
                '${h['houseName'] ?? ''}',
                h['capacity'] == null ? null : _int(h['capacity']),
                _int(h['occupied']),
              ),
        ];
        _existingNames = [
          for (final n in (m['existingFlockNames'] is List ? m['existingFlockNames'] as List : const []))
            '$n',
        ];
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Could not load this batch.';
        });
      }
    }
  }

  void _chooseBatch(int id) {
    _clearRows();
    setState(() => _step = _Step.allocate);
    _loadContext(id);
  }

  void _clearRows() {
    for (final r in _rows) {
      r.dispose();
    }
    _rows.clear();
    _note = '';
    _serverErrors = {};
  }

  String _defaultName(String house) {
    final code = _batchCode.trim();
    if (code.isEmpty) return house.trim();
    if (house.trim().isEmpty) return code;
    return '$code - ${house.trim()}';
  }

  bool _selected(int houseId) => _rows.any((r) => r.houseId == houseId);

  void _toggleHouse(_House h, bool on) => setState(() {
        _note = '';
        _serverErrors = {};
        if (!on) {
          final i = _rows.indexWhere((r) => r.houseId == h.id);
          if (i >= 0) _rows.removeAt(i).dispose();
        } else if (!_selected(h.id)) {
          _rows.add(_Row(h.id, _defaultName(h.name)));
        }
      });

  void _selectAll() => setState(() {
        _clearRows();
        _rows.addAll([for (final h in _houses) _Row(h.id, _defaultName(h.name))]);
      });

  void _distributeEqually() => setState(() {
        _serverErrors = {};
        final count = _rows.length;
        if (count == 0 || _available <= 0) {
          for (final r in _rows) {
            r.quantity.text = '';
          }
          _note = '';
          return;
        }
        final base = _available ~/ count;
        final remainder = _available - base * count;
        for (var i = 0; i < count; i++) {
          _rows[i].quantity.text = '${base + (i < remainder ? 1 : 0)}';
        }
        _note = remainder > 0
            ? '${_n(base)} birds each; the first $remainder ${remainder == 1 ? 'pen takes' : 'pens take'} one extra so none are lost.'
            : '${_n(base)} birds each.';
      });

  _House? _house(int id) => _houses.where((h) => h.id == id).firstOrNull;

  bool get _canFill =>
      _rows.isNotEmpty && _rows.every((r) => _house(r.houseId)?.room != null);

  void _fillByCapacity() => setState(() {
        _serverErrors = {};
        var remaining = _available < 0 ? 0 : _available;
        for (final r in _rows) {
          final room = _house(r.houseId)?.room;
          if (room == null) {
            r.quantity.text = '';
            continue;
          }
          final take = room < remaining ? room : remaining;
          remaining -= take;
          r.quantity.text = take > 0 ? '$take' : '';
        }
        _note = 'Each pen filled to its remaining capacity, in order, until the birds ran out. Edit any row.';
      });

  int get _thisAllocation =>
      _rows.fold(0, (s, r) => s + ((_qty(r.quantity.text) ?? 0).clamp(0, 1 << 31)));

  /// validateRows from lib/flocks/allocation.ts.
  ({Map<int, Map<String, String>> rows, String? batch}) get _errors {
    final out = <int, Map<String, String>>{};
    if (_rows.isEmpty) return (rows: out, batch: 'Add at least one house before creating flocks.');
    if (_rows.length > _maxRows) {
      return (
        rows: out,
        batch: 'A single allocation can create at most $_maxRows flocks. Split this into smaller allocations.',
      );
    }
    final existing = {for (final n in _existingNames) _dupKey(n)}..remove('');
    final counts = <String, int>{};
    final perHouse = <int, int>{};
    for (final r in _rows) {
      final k = _dupKey(r.name.text);
      if (k.isNotEmpty) counts[k] = (counts[k] ?? 0) + 1;
      final q = _qty(r.quantity.text);
      if (q != null && q > 0) perHouse[r.houseId] = (perHouse[r.houseId] ?? 0) + q;
    }
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      final e = <String, String>{};
      final name = r.name.text.trim();
      if (name.isEmpty) {
        e['name'] = 'Flock name is required.';
      } else if (name.length > _maxName) {
        e['name'] = 'Flock name cannot be longer than $_maxName characters.';
      } else if ((counts[_dupKey(name)] ?? 0) > 1) {
        e['name'] = '"$name" appears more than once in this allocation.';
      } else if (existing.contains(_dupKey(name))) {
        e['name'] = 'A flock named "$name" already exists on this farm.';
      }
      final q = _qty(r.quantity.text);
      if (q == null) {
        e['quantity'] = 'Enter how many birds go into this house — a whole number.';
      } else if (q <= 0) {
        e['quantity'] = 'Enter how many birds go into this house — more than zero.';
      }
      final h = _house(r.houseId);
      if (h == null) {
        e['houseId'] = 'That house/pen is not available on this farm.';
      } else if (q != null && q > 0) {
        final room = h.room;
        final requested = perHouse[r.houseId] ?? 0;
        if (room != null && requested > room) {
          e['quantity'] = '${h.name} holds ${_n(h.capacity ?? 0)} birds'
              '${h.occupied > 0 ? ' and already holds ${_n(h.occupied)}' : ''}. '
              'This allocation puts ${_n(requested)} in it — ${_n(room)} will fit.';
        }
      }
      if (e.isNotEmpty) out[i] = e;
    }
    final requested = _thisAllocation;
    final batchMsg = requested > _available
        ? 'This allocation places ${_n(requested)} birds but the batch only has ${_n(_available)} left to allocate.'
        : null;
    return (rows: out, batch: batchMsg);
  }

  String? _errorFor(int i, String field, Map<int, Map<String, String>> errs) {
    final m = errs[i]?[field];
    if (m == null) return _serverErrors[i]?[field];
    if (_submitted) return m;
    return m.contains('already exists') || m.contains('more than once') || m.contains('will fit')
        ? m
        : null;
  }

  void _goToReview() {
    setState(() => _submitted = true);
    final errs = _errors;
    if (errs.rows.isNotEmpty || errs.batch != null) {
      final n = errs.rows.length;
      _snack(errs.batch ?? '$n row${n == 1 ? '' : 's'} need attention.');
      return;
    }
    setState(() => _step = _Step.review);
  }

  Future<void> _submit() async {
    final id = _batchId;
    if (id == null) return;
    setState(() => _saving = true);
    try {
      final res = await widget.session.farmClient.post('/api/Flock/bulk-allocate', body: {
        'UserId': widget.session.tokens.userId ?? '',
        'FarmId': widget.company.farmId,
        'BatchId': id,
        'Source': widget.source,
        'Allocations': [
          for (final r in _rows)
            {
              'HouseId': r.houseId,
              'Name': r.name.text.trim(),
              'Quantity': _qty(r.quantity.text) ?? 0,
              'Notes': null,
            },
        ],
      });
      if (!mounted) return;
      final m = res is Map ? res : const {};
      final b = m['batch'] is Map ? m['batch'] as Map : const {};
      setState(() {
        _saving = false;
        _createdCount = _int(m['createdCount']);
        _birdsAllocated = _int(m['birdsAllocated']);
        _remainingAfter = _int(b['unallocatedBirds']);
        _step = _Step.done;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // Someone may have allocated from this batch meanwhile: pin the
      // server's messages to the rows, go back to edit, and reload.
      final fromServer = <int, Map<String, String>>{};
      final body = e.body;
      if (body is Map && body['errors'] is List) {
        for (final err in body['errors'] as List) {
          if (err is! Map) continue;
          final i = int.tryParse('${err['index']}') ?? -1;
          if (i < 0) continue;
          (fromServer[i] ??= {})['${err['field']}'] = '${err['message']}';
        }
      }
      setState(() {
        _saving = false;
        _serverErrors = fromServer;
        _step = _Step.allocate;
      });
      _loadContext(id);
      _snack('No flocks were created. ${e.message}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('No flocks were created. Something went wrong. Nothing was saved.');
    }
  }

  Future<void> _quickAddHouses() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => BulkHouseScreen(
        session: widget.session,
        company: widget.company,
        existingNames: [for (final h in _houses) h.name],
        source: 'Batch Allocation',
      ),
    ));
    if (created == true && _batchId != null) _loadContext(_batchId!);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final subtitle = switch (_step) {
      _Step.batch => 'Pick the batch whose birds you want to divide across your houses/pens.',
      _Step.review => 'Check the allocation before it is created. Nothing has been saved yet.',
      _Step.done => 'The birds are placed and the flocks are ready to use.',
      _Step.allocate =>
        'Choose the houses/pens, set how many birds go into each, then create every flock in one go.',
    };
    final errs = _errors;

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_step == _Step.done ? 'Flocks created' : 'Divide Batch Into Flocks',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Text(subtitle, style: TextStyle(fontSize: 12.5, color: tokens.mutedForeground)),
            const SizedBox(height: 12),
            if (_step == _Step.batch) _batchStep(),
            if (_loading) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 8),
              const Center(child: Text('Loading batch…')),
            ],
            if (_loadError != null && !_loading)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_loadError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (_batchId != null && !_loading && _step != _Step.batch && _step != _Step.done) ...[
              _batchHeader(),
              const SizedBox(height: 12),
            ],
            if (_batchId != null && !_loading && _step == _Step.allocate) ...[
              _housesSection(),
              const SizedBox(height: 12),
              _allocationSection(errs.rows),
            ],
            if (_step == _Step.review) _reviewSection(),
            if (_step == _Step.done) _doneSection(),
            if (_batchId != null && !_loading && (_step == _Step.allocate || _step == _Step.review) && _rows.isNotEmpty) ...[
              const SizedBox(height: 12),
              _totals(errs.batch),
            ],
            const SizedBox(height: 18),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _batchStep() {
    final batches = (_batches ?? const []).where((b) => b.unallocatedBirds > 0).toList();
    return FormSection(title: 'Select a Batch', color: SectionColor.blue, columns: 1, children: [
      if (_batches == null && _loadError == null)
        const AppField(label: '', full: true, child: LinearProgressIndicator())
      else if (batches.isEmpty)
        const AppField(
          label: '',
          full: true,
          child: Text('No batches to divide yet. Record a flock purchase first, then come back here.'),
        )
      else ...[
        AppField(
          label: 'Batch',
          full: true,
          hint: 'How many of those birds are still unallocated is shown once you pick one.',
          child: AppSelect<String>(
            value: null,
            hintText: 'Choose the batch to divide',
            items: [
              for (final b in batches)
                AppSelectItem(
                  value: '${b.batchId}',
                  label: '${b.batchCode} · ${b.batchName} · '
                      '${_n(b.unallocatedBirds)} of ${_n(b.numberOfBirds)} birds left',
                ),
            ],
            onChanged: (v) {
              final id = int.tryParse(v ?? '');
              if (id != null) _chooseBatch(id);
            },
          ),
        ),
      ],
    ]);
  }

  Widget _stat(String label, String value, {Color? color}) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }

  Widget _grid(List<Widget> cells) => LayoutBuilder(
        builder: (context, c) {
          final w = (c.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [for (final cell in cells) SizedBox(width: w, child: cell)],
          );
        },
      );

  Widget _batchHeader() {
    return FormSection(
      title: 'Batch $_batchCode — $_batchName',
      color: SectionColor.slate,
      columns: 1,
      children: [
        AppField(
          label: '',
          full: true,
          child: _grid([
            _stat('Original birds', _n(_original)),
            _stat('Already allocated', _n(_allocated)),
            _stat('Available', _n(_available), color: const Color(0xFF1D4ED8)),
            _stat('Breed', _breed.isEmpty ? '—' : _breed),
            _stat('Start date', _startDate.isEmpty ? '—' : _startDate),
          ]),
        ),
      ],
    );
  }

  Widget _housesSection() {
    final tokens = context.tokens;
    final selected = _rows.length;
    return FormSection(title: 'Choose Houses/Pens · $selected selected', color: SectionColor.blue, columns: 1, children: [
      AppField(
        label: '',
        full: true,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AppButton(
              label: 'Select all',
              variant: AppButtonVariant.outline,
              size: AppButtonSize.sm,
              onPressed: _houses.isEmpty ? null : _selectAll,
            ),
            AppButton(
              label: 'Clear',
              variant: AppButtonVariant.outline,
              size: AppButtonSize.sm,
              onPressed: _rows.isEmpty ? null : () => setState(_clearRows),
            ),
            AppButton(
              label: 'Quickly Add Houses/Pens',
              icon: Icons.add,
              variant: AppButtonVariant.outline,
              size: AppButtonSize.sm,
              onPressed: _quickAddHouses,
            ),
          ],
        ),
      ),
      if (_houses.isEmpty)
        AppField(
          label: '',
          full: true,
          child: Column(
            children: [
              Icon(Icons.home_outlined, size: 40, color: tokens.mutedForeground),
              const SizedBox(height: 6),
              const Text(
                'No houses/pens on this farm yet. Add some above and they will appear here straight away.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        )
      else
        for (final h in _houses)
          AppField(
            label: '',
            full: true,
            child: AppCheckbox(
              value: _selected(h.id),
              onChanged: (v) => _toggleHouse(h, v),
              label: h.name,
              description: [
                h.capacity != null && h.capacity! > 0 ? 'Capacity ${_n(h.capacity!)}' : 'No capacity set',
                if (h.occupied > 0) 'holds ${_n(h.occupied)}',
                if (h.room != null) '${_n(h.room!)} free',
              ].join(' · '),
            ),
          ),
    ]);
  }

  Widget _allocationSection(Map<int, Map<String, String>> errs) {
    final tokens = context.tokens;
    final errorColor = Theme.of(context).colorScheme.error;
    return FormSection(title: 'Allocation', color: SectionColor.indigo, columns: 1, children: [
      if (_rows.isEmpty)
        AppField(
          label: '',
          full: true,
          child: Column(
            children: [
              Icon(Icons.flutter_dash, size: 40, color: tokens.mutedForeground),
              const SizedBox(height: 6),
              const Text('Tick the houses/pens above to start allocating.', textAlign: TextAlign.center),
            ],
          ),
        )
      else ...[
        AppField(
          label: '',
          full: true,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppButton(
                label: 'Distribute Equally',
                icon: Icons.balance,
                variant: AppButtonVariant.outline,
                size: AppButtonSize.sm,
                onPressed: _distributeEqually,
              ),
              AppButton(
                label: 'Fill by Capacity',
                icon: Icons.auto_fix_high,
                variant: AppButtonVariant.outline,
                size: AppButtonSize.sm,
                onPressed: _canFill ? _fillByCapacity : null,
              ),
              if (!_canFill)
                Text('Fill by Capacity needs a capacity on every selected pen.',
                    style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
            ],
          ),
        ),
        if (_note.isNotEmpty)
          AppField(
            label: '',
            full: true,
            child: Text('$_note Every number stays editable.',
                style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
          ),
        for (var i = 0; i < _rows.length; i++)
          AppField(
            label: '',
            full: true,
            child: Builder(builder: (context) {
              final r = _rows[i];
              final h = _house(r.houseId);
              final nameErr = _errorFor(i, 'name', errs);
              final qtyErr = _errorFor(i, 'quantity', errs);
              final houseErr = _errorFor(i, 'houseId', errs);
              final bad = nameErr != null || qtyErr != null || houseErr != null;
              Widget err(String? m) => m == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(m, style: TextStyle(fontSize: 12, color: errorColor)),
                    );
              void changed(_) => setState(() => _serverErrors = {});
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: bad ? errorColor.withValues(alpha: .5) : tokens.border),
                  borderRadius: BorderRadius.circular(Dim.radiusMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(h?.name ?? 'House ${r.houseId}',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        Text(
                          h?.capacity != null && h!.capacity! > 0
                              ? '${_n(h.capacity!)}${h.room != null ? ' · ${_n(h.room!)} free' : ''}'
                              : 'Not set',
                          style: TextStyle(fontSize: 12, color: tokens.mutedForeground),
                        ),
                      ],
                    ),
                    err(houseErr),
                    const SizedBox(height: 8),
                    AppField(
                      label: 'Flock Name',
                      required: true,
                      child: AppInput(
                        controller: r.name,
                        hintText: _defaultName(h?.name ?? ''),
                        onChanged: changed,
                      ),
                    ),
                    err(nameErr),
                    const SizedBox(height: 6),
                    AppField(
                      label: 'Birds to Place',
                      required: true,
                      child: AppNumberInput(controller: r.quantity, hintText: '0', onChanged: changed),
                    ),
                    err(qtyErr),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: errorColor),
                        onPressed: () => setState(() {
                          _rows.removeAt(i).dispose();
                          _serverErrors = {};
                        }),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Remove'),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
      ],
    ]);
  }

  Widget _reviewSection() {
    final tokens = context.tokens;
    final count = _rows.length;
    final remaining = (_available - _thisAllocation).clamp(0, 1 << 31);
    return FormSection(title: 'Review', color: SectionColor.indigo, columns: 1, children: [
      AppField(
        label: '',
        full: true,
        child: Text(
          '$count ${count == 1 ? 'flock' : 'flocks'} will be created, placing '
          '${_n(_thisAllocation)} birds from $_batchCode.',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
      for (final r in _rows)
        AppField(
          label: '',
          full: true,
          child: Row(
            children: [
              Expanded(
                child: Text(r.name.text.trim(),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
              ),
              Text(
                '${_house(r.houseId)?.name ?? 'House ${r.houseId}'} · ${_n(_qty(r.quantity.text) ?? 0)} birds',
                style: TextStyle(fontSize: 13, color: tokens.mutedForeground),
              ),
            ],
          ),
        ),
      if (remaining > 0)
        AppField(
          label: '',
          full: true,
          child: Text('${_n(remaining)} birds stay unallocated — you can come back and place them later.',
              style: TextStyle(fontSize: 13, color: tokens.mutedForeground)),
        ),
    ]);
  }

  Widget _doneSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5), // emerald-50
        border: Border.all(color: const Color(0xFFA7F3D0)), // emerald-200
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_outline, size: 40, color: Color(0xFF059669)),
          const SizedBox(height: 8),
          Text(
            _createdCount == 1 ? '1 flock created successfully.' : '$_createdCount flocks created successfully.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF064E3B)),
          ),
          const SizedBox(height: 4),
          Text('${_n(_birdsAllocated)} birds allocated from ${_batchCode.isEmpty ? 'the batch' : _batchCode}.',
              textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF065F46))),
          Text('${_n(_remainingAfter)} birds remain unallocated.',
              textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF065F46))),
        ],
      ),
    );
  }

  Widget _totals(String? batchError) {
    final tokens = context.tokens;
    final over = _thisAllocation > _available;
    final error = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: over ? error.withValues(alpha: .06) : tokens.card,
        border: Border.all(color: over ? error.withValues(alpha: .5) : tokens.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _grid([
            _stat('Batch birds', _n(_original)),
            _stat('Previously allocated', _n(_allocated)),
            _stat('This allocation', _n(_thisAllocation), color: over ? error : const Color(0xFF1D4ED8)),
            _stat('Remaining unallocated', _n((_available - _thisAllocation).clamp(0, 1 << 31))),
          ]),
          if (batchError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(batchError, style: TextStyle(fontSize: 13, color: error)),
            ),
        ],
      ),
    );
  }

  Widget _footer() {
    Widget pair(Widget a, Widget b) => Row(children: [
          Expanded(child: a),
          const SizedBox(width: 12),
          Expanded(child: b),
        ]);
    switch (_step) {
      case _Step.done:
        return AppButton(
          label: 'View Flocks',
          size: AppButtonSize.lg,
          fullWidth: true,
          onPressed: () => Navigator.of(context).pop(true),
        );
      case _Step.review:
        return pair(
          AppButton(
            label: 'Back & Edit',
            icon: Icons.arrow_back,
            variant: AppButtonVariant.outline,
            size: AppButtonSize.lg,
            fullWidth: true,
            onPressed: _saving ? null : () => setState(() => _step = _Step.allocate),
          ),
          AppButton(
            label: 'Create ${_rows.length} ${_rows.length == 1 ? 'Flock' : 'Flocks'}',
            size: AppButtonSize.lg,
            fullWidth: true,
            busy: _saving,
            onPressed: _saving ? null : _submit,
          ),
        );
      case _Step.batch:
      case _Step.allocate:
        return pair(
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.destructive,
            size: AppButtonSize.lg,
            fullWidth: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
          AppButton(
            label: 'Review & Create',
            size: AppButtonSize.lg,
            fullWidth: true,
            onPressed: _rows.isEmpty || _loading ? null : _goToReview,
          ),
        );
    }
  }
}
