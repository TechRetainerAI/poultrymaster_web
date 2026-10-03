import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/form_section.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../lookup_loader.dart';

/// Poultry → Setup → Production → Feed Formulas → New / Edit, as the dialog
/// in `app/poultry-feed-formulas/page.tsx`: the formula, then its ingredient
/// lines — each a percentage of the batch or a fixed quantity — with the
/// running percentage total that should reach 100%.
///
/// Create and update are the same `POST /api/Poultry/feed-formulas` (an
/// upsert keyed on poultryFeedFormulaId). Editing loads the full formula,
/// since the list rows carry no lines.
class FeedFormulaFormScreen extends StatefulWidget {
  const FeedFormulaFormScreen({super.key, required this.session, required this.company, this.existing});
  final Session session;
  final Company company;
  final Map<String, dynamic>? existing;

  @override
  State<FeedFormulaFormScreen> createState() => _FeedFormulaFormScreenState();
}

/// RAW_MATERIAL_UNITS in lib/units.ts.
const _units = [
  'Bag', 'Sack', 'Tonne', 'Kilogram', 'Gram', 'Litre', 'Millilitre', 'Bottle',
  'Sachet', 'Piece', 'Pack', 'Carton', 'Box', 'Bundle', 'Dozen', 'Crate', 'Unit', 'Other',
];

class _Line {
  _Line({this.itemId = '', this.mode = 'Percentage', String value = '', this.unit = '', String notes = ''})
      : value = TextEditingController(text: value),
        notes = TextEditingController(text: notes);
  String itemId;
  String mode;
  String unit;
  final TextEditingController value;
  final TextEditingController notes;
  double get amount => double.tryParse(value.text.trim()) ?? 0;
  void dispose() {
    value.dispose();
    notes.dispose();
  }
}

/// Category tests from the web: finished feed vs an ingredient.
bool _isFinished(Object? c) => RegExp('finish', caseSensitive: false).hasMatch('${c ?? ''}');
bool _isIngredient(Object? c) =>
    RegExp('feed', caseSensitive: false).hasMatch('${c ?? ''}') && !_isFinished(c);

class _FeedFormulaFormScreenState extends State<FeedFormulaFormScreen> {
  final _name = TextEditingController();
  final _notes = TextEditingController();
  String _finishedId = '';
  String _outputUnit = '';
  bool _active = true;
  final List<_Line> _lines = [_Line()];

  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  bool _saving = false;
  int? _formulaId;

  Map<String, dynamic> get _scope => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _load() async {
    final client = widget.session.farmClient;
    try {
      final res = await client.get('/api/Poultry/raw-material-items', query: _scope);
      _items = [
        for (final it in LookupLoader.rowsIn(res))
          if (it is Map && it['isActive'] != false) Map<String, dynamic>.from(it),
      ];
    } catch (_) {}
    final id = widget.existing?['poultryFeedFormulaId'];
    if (id != null) {
      try {
        final f = await client.get('/api/Poultry/feed-formulas/$id', query: _scope);
        if (f is Map) {
          _formulaId = int.tryParse('${f['poultryFeedFormulaId']}');
          _name.text = '${f['formulaName'] ?? ''}';
          _finishedId = f['finishedFeedItemId'] == null ? '' : '${f['finishedFeedItemId']}';
          _outputUnit = '${f['defaultOutputUnit'] ?? ''}';
          _notes.text = '${f['notes'] ?? ''}';
          _active = f['isActive'] != false;
          final lines = f['lines'] is List ? f['lines'] as List : const [];
          if (lines.isNotEmpty) {
            for (final l in _lines) {
              l.dispose();
            }
            _lines
              ..clear()
              ..addAll([
                for (final l in lines)
                  if (l is Map)
                    _Line(
                      itemId: '${l['ingredientItemId'] ?? ''}',
                      mode: '${l['quantityMode'] ?? 'Percentage'}',
                      value: '${(l['quantityMode'] == 'Percentage' ? l['percentage'] : l['fixedQuantity']) ?? ''}',
                      unit: '${l['unitOfMeasure'] ?? ''}',
                      notes: '${l['notes'] ?? ''}',
                    ),
              ]);
          }
        }
      } on ApiException catch (e) {
        if (mounted) _snack('Failed to open formula. ${e.message}');
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return _snack('Formula name is required');
    final lines = _lines.where((l) => l.itemId.isNotEmpty && l.amount > 0).toList();
    if (lines.isEmpty) return _snack('Add at least one ingredient line');
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Poultry/feed-formulas', body: {
        'farmId': widget.company.farmId,
        'userId': widget.session.tokens.userId ?? '',
        if (_formulaId != null) 'poultryFeedFormulaId': _formulaId,
        'formulaName': _name.text.trim(),
        'finishedFeedItemId': int.tryParse(_finishedId),
        'defaultOutputUnit': _outputUnit.isEmpty ? null : _outputUnit,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'isActive': _active,
        'lines': [
          for (var i = 0; i < lines.length; i++)
            {
              'ingredientItemId': int.parse(lines[i].itemId),
              'quantityMode': lines[i].mode,
              'percentage': lines[i].mode == 'Percentage' ? lines[i].amount : null,
              'fixedQuantity': lines[i].mode == 'FixedQuantity' ? lines[i].amount : null,
              'unitOfMeasure': lines[i].unit.isEmpty ? null : lines[i].unit,
              'sortOrder': i,
              'notes': lines[i].notes.text.trim().isEmpty ? null : lines[i].notes.text.trim(),
            },
        ],
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
      _snack(_formulaId != null ? 'Formula updated' : 'Formula created');
    } on ApiException catch (e) {
      if (mounted) setState(() => _saving = false);
      _snack('Failed to save formula. ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final finished = _items.where((i) => _isFinished(i['category'])).toList();
    final ingredients = _items.where((i) => _isIngredient(i['category'])).toList();
    final pctLines = _lines.where((l) => l.mode == 'Percentage');
    final pctTotal = pctLines.fold<double>(0, (s, l) => s + l.amount);
    final pctOk = pctLines.isEmpty || (pctTotal - 100).abs() < 0.01;
    final fixed = _lines.where((l) => l.mode == 'FixedQuantity').toList();
    final fixedTotal = fixed.fold<double>(0, (s, l) => s + l.amount);
    final fixedUnits = {for (final l in fixed) if (l.unit.trim().isNotEmpty) l.unit.trim()};

    return Scaffold(
      appBar: AppBar(title: Text(widget.existing != null ? 'Edit Feed Formula' : 'New Feed Formula')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
              children: [
                FormSection(title: 'Formula details', color: SectionColor.blue, stackOnMobile: true, children: [
                  AppField(label: 'Formula name', required: true,
                      child: AppInput(controller: _name, hintText: 'e.g. Layer Mash Formula')),
                  AppField(
                    label: 'Finished feed (optional)',
                    hint: 'Formulas are reusable — leave blank to use with any finished feed',
                    child: AppSelect<String>(
                      value: _finishedId,
                      items: [
                        const AppSelectItem(value: '', label: 'Any finished feed (reusable)'),
                        for (final i in finished)
                          AppSelectItem(value: '${i['poultryRawMaterialItemId']}', label: '${i['itemName'] ?? ''}'),
                      ],
                      onChanged: (v) => setState(() => _finishedId = v ?? ''),
                    ),
                  ),
                  AppField(
                    label: 'Default output unit',
                    hint: "Used as the batch's output unit when this formula is applied",
                    child: AppSelect<String>(
                      value: _outputUnit,
                      items: [
                        const AppSelectItem(value: '', label: 'No default'),
                        for (final u in {if (_outputUnit.isNotEmpty) _outputUnit, ..._units})
                          AppSelectItem(value: u, label: u),
                      ],
                      onChanged: (v) => setState(() => _outputUnit = v ?? ''),
                    ),
                  ),
                  AppField(
                    label: 'Active',
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Switch(value: _active, onChanged: (v) => setState(() => _active = v)),
                    ),
                  ),
                  AppField(label: 'Notes', full: true, child: AppTextarea(controller: _notes, rows: 2)),
                ]),
                const SizedBox(height: 12),
                FormSection(title: 'Ingredients', color: SectionColor.emerald, columns: 1, children: [
                  for (final l in _lines)
                    AppField(label: '', full: true, child: _lineCard(l, ingredients)),
                  AppField(
                    label: '',
                    full: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppButton(
                          label: 'Add ingredient',
                          icon: Icons.add,
                          variant: AppButtonVariant.outline,
                          size: AppButtonSize.sm,
                          onPressed: () => setState(() => _lines.add(_Line())),
                        ),
                        const SizedBox(height: 8),
                        if (pctLines.isNotEmpty)
                          Row(
                            children: [
                              Icon(pctOk ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                                  size: 16,
                                  color: pctOk ? const Color(0xFF047857) : const Color(0xFFB45309)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Percentage total: ${_trim(pctTotal, 2)}%${pctOk ? '' : ' (should be 100%)'}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: pctOk ? const Color(0xFF047857) : const Color(0xFFB45309),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (fixed.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Fixed total: ${_trim(fixedTotal, 3)}'
                              '${fixedUnits.length == 1 ? ' ${fixedUnits.first}' : ''}'
                              '${pctLines.isNotEmpty ? ' (shares the leftover of the batch)' : ' (base recipe — scales to any batch size)'}',
                              style: TextStyle(fontSize: 13, color: tokens.mutedForeground),
                            ),
                          ),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Cancel',
                        variant: AppButtonVariant.outline,
                        size: AppButtonSize.lg,
                        fullWidth: true,
                        onPressed: _saving ? null : () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        label: 'Save Formula',
                        icon: Icons.science_outlined,
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

  static String _trim(double v, int digits) {
    final s = v.toStringAsFixed(digits);
    return s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : s;
  }

  Widget _lineCard(_Line l, List<Map<String, dynamic>> ingredients) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(Dim.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppField(
            label: 'Ingredient',
            child: AppSelect<String>(
              value: l.itemId.isEmpty ? null : l.itemId,
              hintText: ingredients.isEmpty ? 'No ingredient items' : 'Pick ingredient',
              items: [
                for (final i in ingredients)
                  AppSelectItem(value: '${i['poultryRawMaterialItemId']}', label: '${i['itemName'] ?? ''}'),
              ],
              // pickIngredient: the line takes the item's unit of measure.
              onChanged: (v) => setState(() {
                l.itemId = v ?? '';
                final item = ingredients.where((i) => '${i['poultryRawMaterialItemId']}' == v).firstOrNull;
                l.unit = '${item?['unitOfMeasure'] ?? ''}';
              }),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppField(
                  label: 'Mode',
                  child: AppSelect<String>(
                    value: l.mode,
                    items: const [
                      AppSelectItem(value: 'Percentage', label: 'Percentage (%)'),
                      AppSelectItem(value: 'FixedQuantity', label: 'Fixed quantity'),
                    ],
                    onChanged: (v) => setState(() => l.mode = v ?? l.mode),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppField(
                  label: l.mode == 'Percentage' ? 'Percent' : 'Qty${l.unit.isNotEmpty ? ' (${l.unit})' : ''}',
                  child: AppNumberInput(
                    controller: l.value,
                    allowDecimal: true,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AppField(label: 'Notes', child: AppInput(controller: l.notes)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              // A formula keeps at least one line, as on the web.
              onPressed: _lines.length <= 1
                  ? null
                  : () => setState(() {
                        _lines.remove(l);
                        l.dispose();
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
