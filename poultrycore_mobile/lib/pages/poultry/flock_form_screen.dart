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
import 'breed_picker.dart';

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

  List<_Batch>? _batches;
  List<_House>? _houses;
  List<Map<String, dynamic>> _flocks = const [];
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
      if (!mounted) return;
      setState(() {
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
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (_) {
      if (mounted) setState(() => _loadError = 'Could not load batches and houses.');
    }
  }

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
    if (_qty <= 0) {
      return _fail('Enter how many birds are in this flock — use a number greater than zero.');
    }
    if (_batchId == null) {
      return _fail('Link this flock to a batch so bird counts stay accurate.');
    }
    final batch = _selectedBatch;
    if (!_editing && batch != null && _qty > batch.birds) {
      return _fail('That batch only has ${batch.birds} birds available — '
          'lower the flock size or pick another batch.');
    }
    // Room capacity: cannot place more birds than the house holds.
    final house = _houses?.where((h) => h.id == _houseId).firstOrNull;
    if (house != null && house.capacity > 0) {
      final occupied = _flocks
          .where((f) =>
              _int(f['houseId']) == house.id &&
              f['active'] == true &&
              _int(f['flockId']) != (_flockId ?? -1))
          .fold<int>(0, (s, f) => s + _int(f['quantity']));
      if (occupied + _qty > house.capacity) {
        return _fail('${house.name} holds ${house.capacity} birds'
            '${occupied > 0 ? ' and already has $occupied' : ''}. '
            "You're trying to place ${occupied + _qty}. "
            'Reduce the number or pick another room.');
      }
    }

    setState(() => _saving = true);
    final d = _startDate!;
    final body = <String, dynamic>{
      ..._scope,
      if (_editing) 'flockId': _flockId,
      'name': _name.text.trim(),
      'startDate':
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      'breed': _breed.trim(),
      'quantity': _qty,
      'active': _active,
      'hasArrived': _hasArrived,
      'houseId': _houseId,
      'batchId': _batchId,
      'inactivationReason': _inactivationReason,
      'otherReason': _inactivationReason == 'other' ? _otherReason.text.trim() : '',
      'notes': _notes.text.trim(),
    };
    try {
      final client = widget.session.farmClient;
      if (_editing) {
        await client.put('/api/Flock/$_flockId', body: body);
      } else {
        await client.post('/api/Flock', body: body);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_editing ? 'Flock updated successfully.' : 'Flock created successfully.')));
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
            FormSection(title: 'Flock Information', color: SectionColor.indigo, children: [
              AppField(
                label: 'Assign to Flock Batch',
                required: true,
                hint: batch == null ? null : 'Available: ${batch.birds} birds',
                child: AppSelect<String>(
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
                label: 'Start Date',
                required: true,
                child: AppDateField(
                  value: _startDate,
                  onChanged: (d) => setState(() => _startDate = d),
                ),
              ),
              AppField(
                label: 'Number of Birds',
                required: true,
                hint: batch == null ? null : 'Remaining: ${batch.birds - _qty} birds',
                child: AppNumberInput(
                  controller: _quantity,
                  hintText: 'e.g., 100',
                  validator: _req,
                ),
              ),
              AppField(
                label: 'Assign to House',
                child: AppSelect<String>(
                  value: _houseId?.toString() ?? '',
                  enabled: !loading,
                  items: [
                    const AppSelectItem(value: '', label: 'No house'),
                    for (final h in _houses ?? const <_House>[])
                      AppSelectItem(value: '${h.id}', label: h.name),
                  ],
                  onChanged: (v) => setState(() => _houseId = int.tryParse(v ?? '')),
                ),
              ),
            ]),
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
