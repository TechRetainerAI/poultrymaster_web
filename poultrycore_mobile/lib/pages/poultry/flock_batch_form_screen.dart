import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/form_section.dart';
import '../../design/ui/inputs.dart';
import '../../design/web_mobile.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../lookup_loader.dart';
import 'breed_picker.dart';

/// Flock Purchases (Batches) → Add / Edit batch, as the web's dialogs in
/// `app/flock-batch/page.tsx` built from `components/poultry/batch-purchase-fields.tsx`:
/// Batch Details, Purchase Details (with the cash account the payment comes
/// out of), Order & Delivery with the Total / Paid / Balance strip, and
/// Status & Notes. Saves to `/api/MainFlockBatch`.
///
/// The extracted form sent "Batch Has Arrived" as `active`, never sent a
/// status, and left Total Cost for the user to work out.
class FlockBatchFormScreen extends StatefulWidget {
  const FlockBatchFormScreen({
    super.key,
    required this.session,
    required this.company,
    this.existing,
  });

  final Session session;
  final Company company;
  final Map<String, dynamic>? existing;

  @override
  State<FlockBatchFormScreen> createState() => _FlockBatchFormScreenState();
}

class _FlockBatchFormScreenState extends State<FlockBatchFormScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _birds = TextEditingController();
  final _costPerChick = TextEditingController();
  final _total = TextEditingController();
  final _paid = TextEditingController();
  final _rate = TextEditingController();
  final _notes = TextEditingController();

  String _breed = '';
  DateTime? _startDate;
  DateTime? _orderDate;
  DateTime? _arrivalDate;
  String _supplierType = 'local';
  String _supplierId = '';
  String _cashAccountId = '';
  bool _hasArrived = false;
  bool _active = true;

  List<AppSelectItem<String>>? _suppliers;
  List<AppSelectItem<String>>? _accounts;
  List<String> _knownBreeds = const [];

  bool _saving = false;
  String? _error;

  Map<String, dynamic>? get _row => widget.existing;
  bool get _editing => _row != null;

  @override
  void initState() {
    super.initState();
    final r = _row;
    if (r != null) {
      String s(String k) => r[k] == null ? '' : '${r[k]}';
      _name.text = s('batchName');
      _code.text = s('batchCode');
      _breed = s('breed');
      _birds.text = s('numberOfBirds');
      _costPerChick.text = s('costPerChick');
      _total.text = s('totalCost');
      _paid.text = s('amountPaid');
      _rate.text = s('dollarConversionRate');
      _notes.text = s('notes');
      _supplierType = s('supplierType').isEmpty ? 'local' : s('supplierType').toLowerCase();
      _supplierId = s('supplierId') == '0' ? '' : s('supplierId');
      _cashAccountId = s('poultryCashAccountId') == '0' ? '' : s('poultryCashAccountId');
      _startDate = DateTime.tryParse(s('startDate'));
      _orderDate = DateTime.tryParse(s('orderPlacementDate'));
      _arrivalDate = DateTime.tryParse(s('estimatedArrivalDate'));
      // batchTogglesFromStatus
      switch ((s('status').isEmpty ? 'active' : s('status')).toLowerCase()) {
        case 'pending':
          _hasArrived = false;
          _active = true;
        case 'inactive':
          _hasArrived = true;
          _active = false;
        default:
          _hasArrived = true;
          _active = true;
      }
    }
    for (final c in [_total, _paid]) {
      c.addListener(() => setState(() {}));
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _code, _birds, _costPerChick, _total, _paid, _rate, _notes]) {
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

  Future<void> _load() async {
    Future<List<Map<String, dynamic>>> safe(String p) =>
        _list(p).catchError((_) => <Map<String, dynamic>>[]);
    final r = await Future.wait([
      safe('/api/Supplier'),
      safe('/api/Poultry/cash-accounts'),
      safe('/api/MainFlockBatch'),
    ]);
    if (!mounted) return;
    setState(() {
      _suppliers = [
        for (final s in r[0])
          if (s['supplierId'] != null)
            AppSelectItem(value: '${s['supplierId']}', label: '${s['name'] ?? s['supplierId']}'),
      ];
      _accounts = [
        for (final a in r[1])
          if (a['poultryCashAccountId'] != null)
            AppSelectItem(
              value: '${a['poultryCashAccountId']}',
              label: '${a['accountName'] ?? ''} (${_money(_num('${a['currentBalance'] ?? 0}'))})',
            ),
      ];
      _knownBreeds = {
        for (final b in r[2])
          if ('${b['breed'] ?? ''}'.trim().isNotEmpty) '${b['breed']}'.trim(),
      }.toList();
    });
  }

  static double _num(String raw) => double.tryParse(raw.trim()) ?? 0;

  static String _money(double v) => ghc(v).replaceFirst('GHC ', '');

  /// patchForCostChange: typing either side of cost × birds recomputes the
  /// total; an explicit edit of the total wins until the next such change.
  void _recomputeTotal() {
    final total = _num(_costPerChick.text) * _num(_birds.text);
    if (total > 0) _total.text = '${double.parse(total.toStringAsFixed(2))}'.replaceFirst(RegExp(r'\.0$'), '');
  }

  String get _status => !_hasArrived ? 'pending' : (_active ? 'active' : 'inactive');

  static String? _day(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _fail(String msg) {
    setState(() => _error = msg);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (_name.text.trim().isEmpty || _code.text.trim().isEmpty || _startDate == null) {
      return _fail('Fill in batch name, batch code, and start date — they help track birds from arrival.');
    }
    final birds = int.tryParse(_birds.text.trim()) ?? 0;
    if (birds <= 0) {
      return _fail('Enter how many birds arrived in this batch — use a number greater than zero.');
    }
    final cost = _num(_costPerChick.text);
    final total = _total.text.trim().isEmpty ? cost * birds : _num(_total.text);
    final body = <String, dynamic>{
      'UserId': widget.session.tokens.userId ?? '',
      'FarmId': widget.company.farmId,
      'BatchName': _name.text.trim(),
      'BatchCode': _code.text.trim(),
      'StartDate': _day(_startDate),
      'Breed': _breed,
      'NumberOfBirds': birds,
      'CostPerChick': cost,
      'TotalCost': total,
      'AmountPaid': _num(_paid.text),
      'SupplierType': _supplierType,
      'SupplierId': int.tryParse(_supplierId),
      'Status': _status,
      'Notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'DollarConversionRate': _rate.text.trim().isEmpty ? null : _num(_rate.text),
      'OrderPlacementDate': _day(_orderDate),
      'EstimatedArrivalDate': _day(_arrivalDate),
      'PoultryCashAccountId': int.tryParse(_cashAccountId),
    };
    setState(() => _saving = true);
    try {
      final client = widget.session.farmClient;
      if (_editing) {
        final id = _row!['batchId'];
        await client.put('/api/MainFlockBatch/$id', body: {'BatchId': id, ...body});
      } else {
        await client.post('/api/MainFlockBatch', body: body);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_editing ? 'Flock batch updated successfully.' : 'Flock batch created successfully.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _fail(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _fail('Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final total = _num(_total.text);
    final paid = _num(_paid.text);
    final balance = total - paid;
    final (statusLabel, statusColor) = switch (_status) {
      'pending' => ('Pending', const Color(0xFFD97706)),
      'inactive' => ('Inactive', const Color(0xFF64748B)),
      _ => ('Active', const Color(0xFF059669)),
    };

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_editing ? 'Edit Flock Batch' : 'Add New Flock Batch',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(
              _editing ? 'Update the flock batch information below' : 'Enter the flock batch information below',
              style: TextStyle(fontSize: 11.5, color: tokens.mutedForeground),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 12),
          ],
          FormSection(title: 'Batch Details', color: SectionColor.indigo, children: [
            AppField(label: 'Batch Name', required: true,
                child: AppInput(controller: _name, hintText: 'e.g., Batch A - Rhode Island Reds')),
            AppField(label: 'Batch Code', required: true,
                child: AppInput(controller: _code, hintText: 'e.g., B-001')),
            AppField(
              label: 'Breed',
              child: BreedPicker(
                value: _breed,
                known: _knownBreeds,
                onChanged: (v) => setState(() => _breed = v),
              ),
            ),
            AppField(label: 'Start Date', required: true,
                child: AppDateField(value: _startDate, onChanged: (d) => setState(() => _startDate = d))),
            AppField(
              label: 'Number of Birds',
              required: true,
              child: AppNumberInput(
                controller: _birds,
                hintText: 'e.g., 100',
                onChanged: (_) => setState(_recomputeTotal),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          FormSection(title: 'Purchase Details', color: SectionColor.emerald, children: [
            AppField(
              label: 'Cost Per Chick',
              child: AppNumberInput(
                controller: _costPerChick,
                allowDecimal: true,
                onChanged: (_) => setState(_recomputeTotal),
              ),
            ),
            AppField(label: 'Total Cost',
                child: AppNumberInput(controller: _total, allowDecimal: true, hintText: 'Auto-calculated')),
            AppField(
              label: 'Amount Paid Now',
              hint: 'Part payment is fine — pay the balance later by editing the batch.',
              child: AppNumberInput(controller: _paid, allowDecimal: true),
            ),
            AppField(
              label: 'Type',
              child: AppSelect<String>(
                value: _supplierType == 'foreign' ? 'foreign' : 'local',
                items: const [
                  AppSelectItem(value: 'local', label: 'Local'),
                  AppSelectItem(value: 'foreign', label: 'Foreign'),
                ],
                onChanged: (v) => setState(() => _supplierType = v ?? 'local'),
              ),
            ),
            AppField(
              label: 'Supplier',
              child: AppSelect<String>(
                value: _suppliers == null ? null : _supplierId,
                enabled: _suppliers != null,
                hintText: _suppliers == null ? 'Loading…' : 'No supplier',
                items: [
                  const AppSelectItem(value: '', label: 'No supplier'),
                  ...?_suppliers,
                ],
                onChanged: (v) => setState(() => _supplierId = v ?? ''),
              ),
            ),
            AppField(
              label: 'Pay from cash account',
              hint: "The amount paid comes out of this account's balance.",
              child: AppSelect<String>(
                value: _accounts == null ? null : _cashAccountId,
                enabled: _accounts != null,
                hintText: _accounts == null ? 'Loading…' : 'None (no cash movement)',
                items: [
                  const AppSelectItem(value: '', label: 'None (no cash movement)'),
                  ...?_accounts,
                ],
                onChanged: (v) => setState(() => _cashAccountId = v ?? ''),
              ),
            ),
            // Only meaningful for a foreign purchase, but never hides a rate
            // that is already set.
            if (_supplierType == 'foreign' || _rate.text.trim().isNotEmpty)
              AppField(label: 'Dollar Conversion Rate',
                  child: AppNumberInput(controller: _rate, allowDecimal: true)),
          ]),
          const SizedBox(height: 12),
          FormSection(title: 'Order & Delivery', color: SectionColor.sky, children: [
            AppField(
              label: 'Order Placement Date',
              hint: 'When you placed the order with the supplier.',
              child: AppDateField(value: _orderDate, onChanged: (d) => setState(() => _orderDate = d)),
            ),
            AppField(
              label: 'Estimated Arrival Date',
              hint: 'When the birds are expected to arrive.',
              child: AppDateField(value: _arrivalDate, onChanged: (d) => setState(() => _arrivalDate = d)),
            ),
            AppField(
              label: '',
              full: true,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tokens.muted,
                  border: Border.all(color: tokens.border),
                  borderRadius: BorderRadius.circular(Dim.radiusMd),
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Total ${_money(total)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('Paid ${_money(paid)}',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF047857))),
                    Text('Balance ${_money(balance)}',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: balance > 0 ? const Color(0xFFDC2626) : const Color(0xFF047857))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: statusColor),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(statusLabel, style: TextStyle(fontSize: 12, color: statusColor)),
                    ),
                  ],
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          FormSection(title: 'Status & Notes', color: SectionColor.green, columns: 1, children: [
            AppField(
              label: '',
              full: true,
              child: AppSwitchRow(
                label: 'Batch Has Arrived',
                description: '(Leave off until birds physically arrive — status stays Pending)',
                value: _hasArrived,
                onChanged: (v) => setState(() => _hasArrived = v),
              ),
            ),
            AppField(
              label: '',
              full: true,
              child: AppSwitchRow(
                label: 'Active Batch',
                description: '(Only applies once the batch has arrived)',
                value: _active,
                onChanged: _hasArrived ? (v) => setState(() => _active = v) : null,
              ),
            ),
            AppField(
              label: 'Notes (Optional)',
              full: true,
              child: AppTextarea(controller: _notes, hintText: 'Add any additional notes about the batch'),
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
                  label: _editing ? 'Update Batch' : 'Create Batch',
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
    );
  }
}
