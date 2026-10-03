import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/form_section.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';

/// Houses → "Add Multiple Houses/Pens", as the web's
/// `components/poultry/bulk-house-dialog.tsx` with the rules of
/// `lib/houses/bulk.ts`: generate a batch, edit any row, create them all in
/// one `POST /api/House/bulk`. The server runs every insert in one
/// transaction, so if one row cannot be created, none are.
///
/// Pops with true when houses were created. [source] is recorded on each
/// house's audit row, as on the web.
class BulkHouseScreen extends StatefulWidget {
  const BulkHouseScreen({
    super.key,
    required this.session,
    required this.company,
    required this.existingNames,
    this.source = 'Houses page',
  });

  final Session session;
  final Company company;

  /// House names already on this farm, for the duplicate check.
  final List<String> existingNames;
  final String source;

  @override
  State<BulkHouseScreen> createState() => _BulkHouseScreenState();
}

const _maxRows = 200;
const _maxName = 100;
const _maxLocation = 200;
const _maxCapacity = 2000000000;

class _Row {
  _Row({String name = '', String capacity = '', String location = ''})
      : name = TextEditingController(text: name),
        capacity = TextEditingController(text: capacity),
        location = TextEditingController(text: location);
  final TextEditingController name;
  final TextEditingController capacity;
  final TextEditingController location;

  void dispose() {
    name.dispose();
    capacity.dispose();
    location.dispose();
  }
}

String _dupKey(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// null = blank, -1 = not a whole number.
int? _parseCapacity(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  if (!RegExp(r'^\d+$').hasMatch(t)) return -1;
  return int.tryParse(t) ?? -1;
}

class _BulkHouseScreenState extends State<BulkHouseScreen> {
  final _count = TextEditingController(text: '10');
  final _prefix = TextEditingController(text: 'Pen');
  final _start = TextEditingController(text: '1');
  final _capacity = TextEditingController();
  final _location = TextEditingController();

  final List<_Row> _rows = [];
  bool _submitted = false;
  bool _saving = false;

  /// Row errors the server rejected the batch with, keyed like the local ones.
  Map<int, Map<String, String>> _serverErrors = {};

  @override
  void dispose() {
    for (final c in [_count, _prefix, _start, _capacity, _location]) {
      c.dispose();
    }
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// validateRows: required, length, duplicates in the batch and on the farm,
  /// whole non-negative capacity.
  ({Map<int, Map<String, String>> rows, String? batch}) get _errors {
    final out = <int, Map<String, String>>{};
    if (_rows.isEmpty) return (rows: out, batch: 'Add at least one house before creating.');
    if (_rows.length > _maxRows) {
      return (
        rows: out,
        batch: 'A single batch can create at most $_maxRows houses. Split this into smaller batches.',
      );
    }
    final existing = {for (final n in widget.existingNames) _dupKey(n)}..remove('');
    final counts = <String, int>{};
    for (final r in _rows) {
      final k = _dupKey(r.name.text);
      if (k.isNotEmpty) counts[k] = (counts[k] ?? 0) + 1;
    }
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      final e = <String, String>{};
      final name = r.name.text.trim();
      if (name.isEmpty) {
        e['houseName'] = 'House name is required.';
      } else if (name.length > _maxName) {
        e['houseName'] = 'House name cannot be longer than $_maxName characters.';
      } else if ((counts[_dupKey(name)] ?? 0) > 1) {
        e['houseName'] = '"$name" appears more than once in this batch.';
      } else if (existing.contains(_dupKey(name))) {
        e['houseName'] = 'A house named "$name" already exists on this farm.';
      }
      final cap = _parseCapacity(r.capacity.text);
      // The input takes digits only, so a negative cannot be typed.
      if (cap == -1) {
        e['capacity'] = 'Capacity must be a whole number.';
      } else if (cap != null && cap > _maxCapacity) {
        e['capacity'] = 'Capacity is too large.';
      }
      if (r.location.text.trim().length > _maxLocation) {
        e['location'] = 'Location cannot be longer than $_maxLocation characters.';
      }
      if (e.isNotEmpty) out[i] = e;
    }
    return (rows: out, batch: null);
  }

  /// Quiet until the first submit, except duplicates — the reason to preview.
  String? _errorFor(int i, String field, Map<int, Map<String, String>> errs) {
    final m = errs[i]?[field];
    if (m == null) return _serverErrors[i]?[field];
    if (_submitted) return m;
    return m.contains('already exists') || m.contains('more than once') ? m : null;
  }

  void _generate() {
    final n = int.tryParse(_count.text.trim()) ?? 0;
    if (n < 1) return _snack('Enter how many houses/pens you need.');
    if (n > _maxRows) {
      return _snack('A single batch can create at most $_maxRows houses/pens. '
          'Generate them in smaller batches.');
    }
    final prefix = _prefix.text.trim();
    final start = int.tryParse(_start.text.trim()) ?? 1;
    setState(() {
      for (final r in _rows) {
        r.dispose();
      }
      _rows
        ..clear()
        ..addAll([
          for (var i = 0; i < n; i++)
            _Row(
              name: prefix.isEmpty ? '${start + i}' : '$prefix ${start + i}',
              capacity: _capacity.text.trim(),
              location: _location.text.trim(),
            ),
        ]);
      _submitted = false;
      _serverErrors = {};
    });
  }

  void _applyAll({bool capacity = false, bool location = false}) => setState(() {
        for (final r in _rows) {
          if (capacity) r.capacity.text = _capacity.text.trim();
          if (location) r.location.text = _location.text.trim();
        }
      });

  Future<void> _submit() async {
    final errs = _errors;
    setState(() {
      _submitted = true;
      _serverErrors = {};
    });
    if (errs.rows.isNotEmpty || errs.batch != null) {
      final n = errs.rows.length;
      return _snack(errs.batch ??
          '$n row${n == 1 ? '' : 's'} need attention before these houses can be created.');
    }
    setState(() => _saving = true);
    try {
      final res = await widget.session.farmClient.post('/api/House/bulk', body: {
        'UserId': widget.session.tokens.userId ?? '',
        'FarmId': widget.company.farmId,
        'Source': widget.source,
        'Houses': [
          for (final r in _rows)
            {
              'HouseName': r.name.text.trim(),
              'Capacity': _parseCapacity(r.capacity.text),
              'Location': r.location.text.trim().isEmpty ? null : r.location.text.trim(),
            },
        ],
      });
      if (!mounted) return;
      final created = res is Map && res['houses'] is List ? (res['houses'] as List).length : _rows.length;
      final msg = res is Map && res['message'] != null
          ? '${res['message']}'
          : '$created houses/pens created successfully.';
      Navigator.of(context).pop(true);
      _snack(msg);
    } on ApiException catch (e) {
      if (!mounted) return;
      // The server re-runs every rule; pin its messages to the same rows.
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
      });
      _snack('No houses were created. ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('No houses were created. Something went wrong. Nothing was saved.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final errs = _errors;
    var total = 0;
    var without = 0;
    for (final r in _rows) {
      final c = _parseCapacity(r.capacity.text);
      if (c == null || c < 0) {
        without++;
      } else {
        total += c;
      }
    }
    final n = _rows.length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add Multiple Houses/Pens',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(widget.company.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: tokens.mutedForeground)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          Text(
            'Generate a batch, edit any row, then create them all at once. Nothing is '
            'saved until you click create — and if one row cannot be created, none of them are.',
            style: TextStyle(fontSize: 12.5, color: tokens.mutedForeground),
          ),
          const SizedBox(height: 12),
          FormSection(title: 'Generate Houses/Pens', color: SectionColor.blue, children: [
            AppField(label: 'No. of Houses/Pens', required: true,
                child: AppNumberInput(controller: _count, hintText: '10')),
            AppField(label: 'Naming Prefix', child: AppInput(controller: _prefix, hintText: 'Pen')),
            AppField(label: 'Starting Number', child: AppNumberInput(controller: _start, hintText: '1')),
            AppField(label: 'Default Capacity (birds)',
                child: AppNumberInput(controller: _capacity, hintText: '2000')),
            AppField(label: 'Default Location', full: true,
                child: AppInput(controller: _location, hintText: 'Layer House A')),
            AppField(
              label: '',
              full: true,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AppButton(label: 'Generate', icon: Icons.auto_fix_high, onPressed: _generate),
                  if (_rows.isNotEmpty) ...[
                    AppButton(
                      label: 'Apply Capacity to All',
                      variant: AppButtonVariant.outline,
                      size: AppButtonSize.sm,
                      onPressed: () => _applyAll(capacity: true),
                    ),
                    AppButton(
                      label: 'Apply Location to All',
                      variant: AppButtonVariant.outline,
                      size: AppButtonSize.sm,
                      onPressed: () => _applyAll(location: true),
                    ),
                  ],
                  Text('Generating replaces the rows below. Everything stays editable.',
                      style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 12),
          FormSection(title: 'Preview & Edit', color: SectionColor.indigo, columns: 1, children: [
            if (_rows.isEmpty)
              AppField(
                label: '',
                full: true,
                child: Column(
                  children: [
                    Icon(Icons.home_outlined, size: 40, color: tokens.mutedForeground),
                    const SizedBox(height: 8),
                    const Text('No rows yet. Generate a batch above, or add a single row.',
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            for (var i = 0; i < _rows.length; i++) AppField(label: '', full: true, child: _rowCard(i, errs.rows)),
            AppField(
              label: '',
              full: true,
              child: Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  label: 'Add Another Row',
                  icon: Icons.add,
                  variant: AppButtonVariant.outline,
                  size: AppButtonSize.sm,
                  onPressed: () => setState(() {
                    _rows.add(_Row(capacity: _capacity.text.trim(), location: _location.text.trim()));
                    _serverErrors = {};
                  }),
                ),
              ),
            ),
          ]),
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n == 1 ? '1 house/pen will be created.' : '$n houses/pens will be created.',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    'Total capacity: $total birds'
                    '${without > 0 ? ' ($without ${without == 1 ? 'row has' : 'rows have'} no capacity set)' : ''}',
                    style: TextStyle(fontSize: 13, color: tokens.mutedForeground),
                  ),
                  if (_submitted && (errs.rows.isNotEmpty || errs.batch != null))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        errs.batch ?? '${errs.rows.length} row${errs.rows.length == 1 ? '' : 's'} need attention.',
                        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                ],
              ),
            ),
          ],
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
                  label: n == 1 ? 'Create 1 House/Pen' : 'Create $n Houses/Pens',
                  size: AppButtonSize.lg,
                  fullWidth: true,
                  busy: _saving,
                  onPressed: _saving || _rows.isEmpty ? null : _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rowCard(int i, Map<int, Map<String, String>> errs) {
    final tokens = context.tokens;
    final r = _rows[i];
    final nameErr = _errorFor(i, 'houseName', errs);
    final capErr = _errorFor(i, 'capacity', errs);
    final locErr = _errorFor(i, 'location', errs);
    final bad = nameErr != null || capErr != null || locErr != null;
    final errorColor = Theme.of(context).colorScheme.error;
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
          AppInput(controller: r.name, hintText: 'Pen 1', onChanged: changed),
          err(nameErr),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppNumberInput(controller: r.capacity, hintText: '2000', onChanged: changed),
                    err(capErr),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppInput(controller: r.location, hintText: 'Layer House A', onChanged: changed),
                    err(locErr),
                  ],
                ),
              ),
            ],
          ),
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
  }
}
