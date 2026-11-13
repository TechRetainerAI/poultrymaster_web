import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../shared/business_dates.dart' show fmtNum, isoDay;
import 'breed_picker.dart';

import 'package:poultrycore_mobile/design/tone.dart';

// "Add Multiple Batches", as the web's components/poultry/bulk-flock-batch-dialog.tsx
// with the rules of lib/flock-batches/bulk.ts: generate rows, edit any of
// them, create all at once. The server re-runs every rule and creates all or
// none (MainFlockBatch/bulk), through the same insert as the single form.

const maxBulkBatches = 100;
const _maxName = 100;
const _maxCode = 25;

class BulkBatchRow {
  BulkBatchRow({this.batchName = '', this.batchCode = '', this.breed = '', this.startDate = '', this.numberOfBirds = '', this.costPerChick = '', this.amountPaid = ''})
      : id = ++_seq;
  static int _seq = 0;
  final int id;
  String batchName, batchCode, breed, startDate, numberOfBirds, costPerChick, amountPaid;
}

String _norm(String? s) => (s ?? '').trim();

/// Per-farm comparison key: case-insensitive, whitespace collapsed.
String bulkDuplicateKey(String? s) => _norm(s).replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Codes are the prefix plus a 3-digit number: "B" + 6 = "B006".
String makeBatchCode(String prefix, int n) => '${_norm(prefix)}${n.toString().padLeft(3, '0')}';

List<BulkBatchRow> generateBatchRows({
  required int count,
  required String namePrefix,
  required String codePrefix,
  required int startNumber,
  String breed = '',
  String startDate = '',
  String numberOfBirds = '',
  String costPerChick = '',
  String amountPaid = '',
}) {
  final n = count.clamp(0, maxBulkBatches);
  final prefix = _norm(namePrefix);
  return [
    for (var i = 0; i < n; i++)
      BulkBatchRow(
        batchName: prefix.isNotEmpty ? '$prefix ${startNumber + i}' : '${startNumber + i}',
        batchCode: makeBatchCode(codePrefix, startNumber + i),
        breed: _norm(breed),
        startDate: startDate,
        numberOfBirds: _norm(numberOfBirds),
        costPerChick: _norm(costPerChick),
        amountPaid: _norm(amountPaid),
      ),
  ];
}

/// The number after the highest existing code of the form `<prefix><digits>`,
/// so a new run carries on the farm's series ("B005" exists → start at 6).
int nextBatchStartNumber(String codePrefix, List<String?> existingCodes) {
  final key = bulkDuplicateKey(codePrefix);
  var highest = 0;
  for (final c in existingCodes) {
    final k = bulkDuplicateKey(c);
    if (!k.startsWith(key)) continue;
    final m = RegExp(r'^(\d+)$').firstMatch(k.substring(key.length));
    if (m != null) {
      final v = int.tryParse(m[1]!);
      if (v != null && v > highest) highest = v;
    }
  }
  return highest + 1;
}

num? _num(String raw) {
  final t = _norm(raw);
  if (t.isEmpty) return 0;
  return num.tryParse(t);
}

double _r2(num n) => (n * 100).round() / 100;

/// Total cost as the single form computes it: cost per chick × birds.
double bulkRowTotal(BulkBatchRow r) {
  final birds = (_num(r.numberOfBirds) ?? 0).floor().clamp(0, 1 << 40);
  return _r2((_num(r.costPerChick) ?? 0) * birds);
}

typedef BulkBatchError = ({int index, String field, String message});

List<BulkBatchError> validateBulkBatches(List<BulkBatchRow> rows, [List<String?> existingCodes = const []]) {
  final errors = <BulkBatchError>[];
  void err(int i, String f, String m) => errors.add((index: i, field: f, message: m));
  if (rows.isEmpty) {
    err(-1, 'batches', 'Add at least one batch.');
    return errors;
  }
  if (rows.length > maxBulkBatches) {
    err(-1, 'batches', 'A single request can create at most $maxBulkBatches batches.');
    return errors;
  }
  final existing = {for (final c in existingCodes) bulkDuplicateKey(c)};
  final seen = <String>{};
  for (final (i, r) in rows.indexed) {
    final name = _norm(r.batchName);
    if (name.isEmpty) {
      err(i, 'batchName', 'Batch name is required.');
    } else if (name.length > _maxName) {
      err(i, 'batchName', 'Batch name cannot be longer than $_maxName characters.');
    }
    final code = _norm(r.batchCode);
    if (code.isEmpty) {
      err(i, 'batchCode', 'Batch code is required.');
    } else if (code.length > _maxCode) {
      err(i, 'batchCode', 'Batch code cannot be longer than $_maxCode characters.');
    } else {
      final key = bulkDuplicateKey(code);
      if (existing.contains(key)) {
        err(i, 'batchCode', 'A batch with code "$code" already exists.');
      } else if (!seen.add(key)) {
        err(i, 'batchCode', '"$code" appears more than once in this list.');
      }
    }
    final birds = _num(r.numberOfBirds);
    if (birds == null || birds != birds.roundToDouble() || birds <= 0) err(i, 'numberOfBirds', 'Number of birds must be greater than 0.');
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(_norm(r.startDate))) err(i, 'startDate', 'Start date is required.');
    final cost = _num(r.costPerChick);
    if (cost == null || cost < 0) err(i, 'costPerChick', 'Cost per chick cannot be negative.');
    final paid = _num(r.amountPaid);
    if (paid == null || paid < 0) {
      err(i, 'amountPaid', 'Amount paid cannot be negative.');
    } else if (paid > 0 && paid > bulkRowTotal(r)) {
      err(i, 'amountPaid', 'Amount paid cannot be more than the total cost.');
    }
  }
  return errors;
}

({int count, int birds, double totalCost, double amountPaid, double balance}) summarizeBulkBatches(List<BulkBatchRow> rows) {
  var birds = 0;
  double cost = 0, paid = 0;
  for (final r in rows) {
    birds += (_num(r.numberOfBirds) ?? 0).floor().clamp(0, 1 << 40);
    cost += bulkRowTotal(r);
    paid += (_num(r.amountPaid) ?? 0).clamp(0, double.infinity);
  }
  return (count: rows.length, birds: birds, totalCost: _r2(cost), amountPaid: _r2(paid), balance: _r2(cost - paid));
}

/// batchStatusFromToggles.
String batchStatusFromToggles(bool hasArrived, bool active) => !hasArrived ? 'pending' : (active ? 'active' : 'inactive');

/// The request rows: every shared setting copied onto every row.
List<Map<String, dynamic>> bulkBatchPayload(List<BulkBatchRow> rows,
    {required String supplierType, int? supplierId, int? cashAccountId, required String status, String notes = ''}) {
  return [
    for (final r in rows)
      {
        'BatchName': _norm(r.batchName),
        'BatchCode': _norm(r.batchCode),
        'Breed': _norm(r.breed),
        'StartDate': _norm(r.startDate),
        'NumberOfBirds': (_num(r.numberOfBirds) ?? 0).floor(),
        'CostPerChick': _num(r.costPerChick) ?? 0,
        'TotalCost': bulkRowTotal(r),
        'AmountPaid': _num(r.amountPaid) ?? 0,
        'SupplierType': supplierType.isEmpty ? 'local' : supplierType,
        'SupplierId': supplierId,
        'PoultryCashAccountId': cashAccountId,
        'Status': status.isEmpty ? 'active' : status,
        'Notes': _norm(notes).isEmpty ? null : _norm(notes),
      },
  ];
}

class BulkFlockBatchScreen extends StatefulWidget {
  const BulkFlockBatchScreen({
    super.key,
    required this.session,
    required this.company,
    required this.existingCodes,
    this.suppliers = const [],
    this.cashAccounts = const [],
    this.knownBreeds = const [],
    this.currencySymbol = '',
  });
  final Session session;
  final Company company;

  /// Batch codes already on this farm, for the duplicate check.
  final List<String> existingCodes;
  final List<Map> suppliers;
  final List<Map> cashAccounts;
  final List<String> knownBreeds;
  final String currencySymbol;

  @override
  State<BulkFlockBatchScreen> createState() => _BulkFlockBatchScreenState();
}

class _BulkFlockBatchScreenState extends State<BulkFlockBatchScreen> {
  final _count = TextEditingController(text: '5');
  final _namePrefix = TextEditingController(text: 'Batch');
  final _codePrefix = TextEditingController(text: 'B');
  late final _startNumber = TextEditingController(text: '${nextBatchStartNumber('B', widget.existingCodes)}');
  String _breed = '';
  String _startDate = isoDay(DateTime.now());
  final _birds = TextEditingController();
  final _cost = TextEditingController();
  final _paid = TextEditingController();
  String _supplierType = 'local';
  int? _supplierId;
  int? _cashAccountId;
  bool _hasArrived = true;
  bool _active = true;
  final _notes = TextEditingController();
  List<BulkBatchRow> _rows = [];
  bool _submitted = false;
  bool _saving = false;
  Map<int, Map<String, String>> _serverErrors = {};
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    for (final c in [_count, _startNumber, _codePrefix]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_count, _namePrefix, _codePrefix, _startNumber, _birds, _cost, _paid, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String _money(num n) {
    final parts = n.abs().toStringAsFixed(2).split('.');
    return '${widget.currencySymbol}${n < 0 ? '-' : ''}${fmtNum(int.parse(parts[0]), 0)}.${parts[1]}';
  }

  void _toast(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  List<BulkBatchError> get _errors => validateBulkBatches(_rows, widget.existingCodes);

  /// Quiet until submit, except duplicate codes (the point of the preview).
  String? _errorFor(int i, String field) {
    final m = _errors.where((e) => e.index == i && e.field == field).firstOrNull?.message;
    if (m == null) return _serverErrors[i]?[field];
    if (_submitted) return m;
    return m.contains('already exists') || m.contains('more than once') ? m : null;
  }

  void _generate() {
    final n = int.tryParse(_count.text.trim());
    if (n == null || n < 1) return _toast('Nothing to generate — Enter how many batches you need.');
    if (n > maxBulkBatches) return _toast('Too many at once — You can create at most $maxBulkBatches batches at a time.');
    setState(() {
      _rows = generateBatchRows(
        count: n,
        namePrefix: _namePrefix.text,
        codePrefix: _codePrefix.text,
        startNumber: int.tryParse(_startNumber.text.trim()) ?? 1,
        breed: _breed,
        startDate: _startDate,
        numberOfBirds: _birds.text,
        costPerChick: _cost.text,
        amountPaid: _paid.text,
      );
      _gen++;
      _submitted = false;
      _serverErrors = {};
    });
  }

  void _applyAll(void Function(BulkBatchRow r) f) => setState(() {
        for (final r in _rows) {
          f(r);
        }
        _gen++;
      });

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _serverErrors = {};
    });
    final errors = _errors;
    if (errors.isNotEmpty) {
      final batch = errors.where((e) => e.index < 0).firstOrNull;
      _toast('Check the rows below — ${batch?.message ?? '${errors.length} row${errors.length == 1 ? '' : 's'} need attention before these batches can be created.'}');
      return;
    }
    setState(() => _saving = true);
    final count = _rows.length;
    try {
      final res = await widget.session.farmClient.post('/api/MainFlockBatch/bulk', body: {
        'UserId': widget.session.tokens.userId ?? '',
        'FarmId': widget.company.farmId,
        'Source': 'Flock Purchases page',
        'Batches': bulkBatchPayload(_rows,
            supplierType: _supplierType,
            supplierId: _supplierId,
            cashAccountId: _cashAccountId,
            status: batchStatusFromToggles(_hasArrived, _active),
            notes: _notes.text),
      });
      if (!mounted) return;
      final msg = res is Map ? '${res['message'] ?? res['Message'] ?? ''}' : '';
      _toast('Batches created — ${msg.isNotEmpty ? msg : '$count batches created.'}');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      final fromServer = <int, Map<String, String>>{};
      final body = e.body;
      final list = body is Map ? (body['errors'] ?? body['Errors']) : null;
      if (list is List) {
        for (final x in list) {
          if (x is! Map) continue;
          final i = int.tryParse('${x['index'] ?? x['Index']}') ?? -1;
          if (i < 0) continue;
          (fromServer[i] ??= {})['${x['field'] ?? x['Field']}'] = '${x['message'] ?? x['Message']}';
        }
      }
      setState(() {
        _serverErrors = fromServer;
        _saving = false;
      });
      _toast('No batches were created — ${e.message.isNotEmpty ? e.message : 'Nothing was saved.'}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = summarizeBulkBatches(_rows);
    final errors = _errors;
    final batchError = errors.where((e) => e.index < 0).firstOrNull;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Add Multiple Batches')),
        body: ListView(key: const ValueKey('bulk-batches-list'), padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          const Text(
            'Generate a list of batches, edit any row, then create them all at once. Nothing is saved until you click create — and '
            'if one batch cannot be created, none of them are.',
            style: TextStyle(fontSize: 13.5, color: _slate500),
          ),
          const SizedBox(height: 14),
          // ---- Generator
          _band('Generate Batches', const Tone.bg(0xFF2563EB), Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _pair(_field('No. of batches *', AppNumberInput(key: const ValueKey('bb-count'), controller: _count)),
                _field('Name prefix', AppInput(key: const ValueKey('bb-name'), controller: _namePrefix, hintText: 'Batch'))),
            _pair(
              _field('Code prefix', AppInput(
                key: const ValueKey('bb-code'),
                controller: _codePrefix,
                onChanged: (v) => _startNumber.text = '${nextBatchStartNumber(v, widget.existingCodes)}',
              )),
              _field('Starting number', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AppNumberInput(key: const ValueKey('bb-start'), controller: _startNumber),
                const SizedBox(height: 2),
                Text('First code: ${_codePrefix.text.trim()}${(int.tryParse(_startNumber.text.trim()) ?? 1).toString().padLeft(3, '0')}',
                    style: const TextStyle(fontSize: 11.5, color: _slate500)),
              ])),
            ),
            _pair(_field('Breed', BreedPicker(value: _breed, known: widget.knownBreeds, onChanged: (v) => setState(() => _breed = v))),
                _field('Start date', AppDateField(value: DateTime.tryParse(_startDate), onChanged: (d) => setState(() => _startDate = d == null ? '' : isoDay(d))))),
            _pair(_field('Birds per batch', AppNumberInput(key: const ValueKey('bb-birds'), controller: _birds, hintText: '1000')),
                _field('Cost per chick', _decimal(_cost, 'bb-cost'))),
            _field('Amount paid per batch (${widget.currencySymbol.isEmpty ? 'amount' : widget.currencySymbol})', _decimal(_paid, 'bb-paid')),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              FilledButton.icon(key: const ValueKey('bb-generate'), onPressed: _generate, icon: const Icon(Icons.auto_fix_high, size: 16), label: const Text('Generate')),
              if (_rows.isNotEmpty) ...[
                OutlinedButton(onPressed: () => _applyAll((r) => r.breed = _breed), child: const Text('Apply breed to all')),
                OutlinedButton(onPressed: () => _applyAll((r) => r.startDate = _startDate), child: const Text('Apply date to all')),
                OutlinedButton(onPressed: () => _applyAll((r) => r.numberOfBirds = _birds.text), child: const Text('Apply birds to all')),
                OutlinedButton(onPressed: () => _applyAll((r) => r.costPerChick = _cost.text), child: const Text('Apply cost to all')),
                OutlinedButton(onPressed: () => _applyAll((r) => r.amountPaid = _paid.text), child: const Text('Apply paid to all')),
                OutlinedButton(
                  onPressed: () => _applyAll((r) {
                    final t = bulkRowTotal(r);
                    r.amountPaid = t == t.roundToDouble() ? '${t.toInt()}' : '$t';
                  }),
                  child: const Text('Mark all fully paid'),
                ),
              ],
              const Text('Generating replaces the rows below. Everything stays editable.', style: TextStyle(fontSize: 12, color: _slate500)),
            ]),
          ])),
          const SizedBox(height: 14),
          // ---- Shared
          _band('Supplier, payment & status — same for every batch', const Tone.bg(0xFF7C3AED), Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _pair(
              _field('Type', AppSelect<String>(
                value: _supplierType,
                items: const [AppSelectItem(value: 'local', label: 'Local'), AppSelectItem(value: 'foreign', label: 'Foreign')],
                onChanged: (v) => setState(() => _supplierType = v ?? 'local'),
              )),
              _field('Supplier', AppSelect<int>(
                value: _supplierId ?? 0,
                items: [
                  const AppSelectItem(value: 0, label: 'No supplier'),
                  for (final s in widget.suppliers)
                    if ((int.tryParse('${s['supplierId']}') ?? 0) > 0) AppSelectItem(value: int.parse('${s['supplierId']}'), label: '${s['name'] ?? ''}'),
                ],
                onChanged: (v) => setState(() => _supplierId = (v ?? 0) == 0 ? null : v),
              )),
            ),
            _field('Pay from cash account', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppSelect<int>(
                value: _cashAccountId ?? 0,
                items: [
                  const AppSelectItem(value: 0, label: 'None (no cash movement)'),
                  for (final a in widget.cashAccounts)
                    if ((int.tryParse('${a['poultryCashAccountId']}') ?? 0) > 0)
                      AppSelectItem(
                        value: int.parse('${a['poultryCashAccountId']}'),
                        label: '${a['accountName']} (${_money(num.tryParse('${a['currentBalance']}') ?? 0)})',
                      ),
                ],
                onChanged: (v) => setState(() => _cashAccountId = (v ?? 0) == 0 ? null : v),
              ),
              const SizedBox(height: 2),
              const Text("Each batch's amount paid comes out of this account.", style: TextStyle(fontSize: 11.5, color: _slate500)),
            ])),
            AppSwitchRow(label: 'Batches have arrived', value: _hasArrived, onChanged: (v) => setState(() => _hasArrived = v)),
            AppSwitchRow(label: 'Active batches', value: _active, onChanged: _hasArrived ? (v) => setState(() => _active = v) : null),
            _field('Notes (optional)', AppInput(controller: _notes, hintText: 'e.g. November chick order')),
          ])),
          const SizedBox(height: 14),
          // ---- Preview & edit
          _band('Preview & Edit', const Tone.bg(0xFF059669), _rows.isEmpty
              ? Column(children: [
                  const Icon(Icons.inventory_2_outlined, size: 32, color: _slate400),
                  const SizedBox(height: 8),
                  const Text('No rows yet. Generate batches above, or add a single row.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: _slate500)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(onPressed: _addRow, icon: const Icon(Icons.add, size: 16), label: const Text('Add a row')),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final (i, r) in _rows.indexed) ...[_rowCard(i, r), const SizedBox(height: 10)],
                  Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: _addRow, icon: const Icon(Icons.add, size: 16), label: const Text('Add another row'))),
                ])),
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              key: const ValueKey('bb-review'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _slate50, border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(summary.count == 1 ? '1 batch will be created.' : '${summary.count} batches will be created.',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: _slate900)),
                const SizedBox(height: 2),
                Text('${fmtNum(summary.birds, 0)} birds · Total cost ${_money(summary.totalCost)} · Paid ${_money(summary.amountPaid)} · Balance ${_money(summary.balance)}',
                    style: const TextStyle(fontSize: 13, color: _slate600)),
                if (_submitted && errors.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(batchError?.message ?? '${errors.length} row${errors.length == 1 ? '' : 's'} need attention.',
                      style: const TextStyle(fontSize: 13, color: Tone.fg(0xFFB91C1C))),
                ],
              ]),
            ),
          ],
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel'))),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                key: const ValueKey('bb-create'),
                onPressed: _saving || _rows.isEmpty ? null : _submit,
                child: Text(_saving ? 'Creating…' : summary.count == 1 ? 'Create 1 Batch' : 'Create ${summary.count} Batches'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  void _addRow() => setState(() {
        _rows.add(BulkBatchRow(breed: _breed, startDate: _startDate, numberOfBirds: _birds.text, costPerChick: _cost.text, amountPaid: _paid.text));
        _serverErrors = {};
      });

  /// One row of the web's table, as a card on the phone.
  Widget _rowCard(int i, BulkBatchRow r) {
    Widget cell(String label, String field, String value, ValueChanged<String> on, {TextInputType? type}) => _field(
          label,
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppInput(
              key: ValueKey('bb-$field-$i-$_gen'),
              initialValue: value,
              keyboardType: type,
              onChanged: (v) => setState(() {
                on(v);
                _serverErrors = {};
              }),
            ),
            if (_errorFor(i, field) case final m?) ...[
              const SizedBox(height: 2),
              Text(m, style: const TextStyle(fontSize: 11.5, color: Tone.fg(0xFFDC2626))),
            ],
          ]),
        );
    return Container(
      key: ValueKey('bb-row-$i'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Tone.bg(0xFFFFFFFF), border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Row ${i + 1} · Total ${_money(bulkRowTotal(r))}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _slate700))),
          IconButton(
            tooltip: 'Remove row',
            onPressed: () => setState(() {
              _rows.removeAt(i);
              _gen++;
              _serverErrors = {};
            }),
            icon: const Icon(Icons.delete_outline, size: 18, color: Tone.fg(0xFFDC2626)),
          ),
        ]),
        _pair(cell('Batch name *', 'batchName', r.batchName, (v) => r.batchName = v), cell('Code *', 'batchCode', r.batchCode, (v) => r.batchCode = v)),
        _pair(
          cell('Breed', 'breed', r.breed, (v) => r.breed = v),
          _field('Start date *', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppDateField(value: DateTime.tryParse(r.startDate), onChanged: (d) => setState(() => r.startDate = d == null ? '' : isoDay(d))),
            if (_errorFor(i, 'startDate') case final m?) Text(m, style: const TextStyle(fontSize: 11.5, color: Tone.fg(0xFFDC2626))),
          ])),
        ),
        _pair(
          cell('Birds *', 'numberOfBirds', r.numberOfBirds, (v) => r.numberOfBirds = v, type: TextInputType.number),
          cell('Cost/chick', 'costPerChick', r.costPerChick, (v) => r.costPerChick = v, type: const TextInputType.numberWithOptions(decimal: true)),
        ),
        cell('Amount paid', 'amountPaid', r.amountPaid, (v) => r.amountPaid = v, type: const TextInputType.numberWithOptions(decimal: true)),
      ]),
    );
  }

  Widget _decimal(TextEditingController c, String key) => AppInput(
        key: ValueKey(key),
        controller: c,
        hintText: '0.00',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      );

  Widget _band(String title, Color color, Widget child) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: _slate50, border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: color,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
          Padding(padding: const EdgeInsets.all(12), child: child),
        ]),
      );

  Widget _field(String label, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _slate700)),
          const SizedBox(height: 4),
          child,
        ]),
      );

  Widget _pair(Widget a, Widget b) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: a),
        const SizedBox(width: 10),
        Expanded(child: b),
      ]);
}

const _slate50 = Tone.bg(0xFFF8FAFC);
const _slate200 = Tone.line(0xFFE2E8F0);
const _slate400 = Tone.fg(0xFF94A3B8);
const _slate500 = Tone.fg(0xFF64748B);
const _slate600 = Tone.fg(0xFF475569);
const _slate700 = Tone.fg(0xFF334155);
const _slate900 = Tone.fg(0xFF0F172A);
