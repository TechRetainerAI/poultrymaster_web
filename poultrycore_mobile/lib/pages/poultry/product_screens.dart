import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/form_section.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../lookup_loader.dart';

/// Poultry → Setup → Production → Products, as `app/poultry-products/page.tsx`.
/// The page has three dialogs, each a screen here: the product itself, its
/// recipe (bill of materials), and "Add stock".

const _productTypes = ['FinishedGood', 'RawMaterial', 'PackagingMaterial', 'Other'];
const _units = [
  'Bag', 'Crate', 'Tray', 'Dozen', 'Egg', 'Piece', 'Kilogram', 'Carton', 'Box', 'Pack', 'Unit', 'Other',
];

Widget _footer(BuildContext context, {required String label, required bool busy, required VoidCallback onSave}) {
  return Row(
    children: [
      Expanded(
        child: AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.outline,
          size: AppButtonSize.lg,
          fullWidth: true,
          onPressed: busy ? null : () => Navigator.of(context).pop(),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: AppButton(label: label, size: AppButtonSize.lg, fullWidth: true, busy: busy,
            onPressed: busy ? null : onSave),
      ),
    ],
  );
}

String _num(Object? v) => v == null ? '' : '$v';

/// New / Edit product. Choosing "raw egg product: Yes" turns recipe setup
/// off, as the web's select does.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, required this.session, required this.company, this.existing});
  final Session session;
  final Company company;
  final Map<String, dynamic>? existing;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _name = TextEditingController();
  final _price = TextEditingController(text: '0');
  final _size = TextEditingController();
  final _sku = TextEditingController();
  String _type = 'FinishedGood';
  String _unit = '';
  bool _rawEgg = false;
  bool _needsRecipe = true;
  bool _saving = false;

  Map<String, dynamic>? get _row => widget.existing;

  @override
  void initState() {
    super.initState();
    final r = _row;
    if (r == null) return;
    _name.text = '${r['name'] ?? ''}';
    _price.text = _num(r['unitPrice'] ?? 0);
    _size.text = '${r['size'] ?? ''}';
    _sku.text = '${r['sku'] ?? ''}';
    _type = _productTypes.contains(r['productType']) ? '${r['productType']}' : 'FinishedGood';
    _unit = '${r['unit'] ?? ''}';
    _rawEgg = r['isRawEggProduct'] == true;
    _needsRecipe = r['requiresRecipeSetup'] != false;
  }

  @override
  void dispose() {
    for (final c in [_name, _price, _size, _sku]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_name.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }
    setState(() => _saving = true);
    final r = _row;
    final body = {
      'farmId': widget.company.farmId,
      'name': _name.text.trim(),
      'sku': _sku.text.trim(),
      'unit': _unit,
      'size': _size.text.trim(),
      'unitPrice': double.tryParse(_price.text.trim()) ?? 0,
      'productType': _type,
      // Not on the form; kept as they are, as the web's EMPTY / openEdit do.
      'isActive': r == null ? true : r['isActive'] != false,
      'notes': '${r?['notes'] ?? ''}',
      'isRawEggProduct': _rawEgg,
      'requiresRecipeSetup': _needsRecipe,
    };
    try {
      final client = widget.session.farmClient;
      if (r != null) {
        final id = r['poultryProductId'];
        await client.put('/api/Poultry/products/$id', body: {...body, 'poultryProductId': id});
      } else {
        await client.post('/api/Poultry/products', body: body);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(SnackBar(content: Text(r != null ? 'Product updated' : 'Product added')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Save failed. ${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_row != null ? 'Edit product' : 'New product')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          FormSection(title: 'Product details', color: SectionColor.blue, children: [
            AppField(label: 'Name', required: true, child: AppInput(controller: _name)),
            AppField(
              label: 'Type',
              child: AppSelect<String>(
                value: _type,
                items: [for (final t in _productTypes) AppSelectItem(value: t, label: t)],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
            ),
            AppField(
              label: 'Unit',
              child: AppSelect<String>(
                // A unit saved before this list existed still shows.
                value: _unit.isEmpty ? null : _unit,
                hintText: 'Pick unit',
                items: [
                  for (final u in {..._units, if (_unit.isNotEmpty) _unit}) AppSelectItem(value: u, label: u),
                ],
                onChanged: (v) => setState(() => _unit = v ?? ''),
              ),
            ),
            AppField(label: 'Selling price',
                child: AppNumberInput(controller: _price, allowDecimal: true)),
            AppField(label: 'Size', hint: 'e.g. Small / Medium / Large / Crate', child: AppInput(controller: _size)),
            AppField(label: 'SKU', child: AppInput(controller: _sku)),
            AppField(
              label: 'Is this a raw egg product?',
              child: AppSelect<String>(
                value: _rawEgg ? 'yes' : 'no',
                items: const [AppSelectItem(value: 'no', label: 'No'), AppSelectItem(value: 'yes', label: 'Yes')],
                onChanged: (v) => setState(() {
                  _rawEgg = v == 'yes';
                  if (_rawEgg) _needsRecipe = false;
                }),
              ),
            ),
            AppField(
              label: 'Requires recipe setup?',
              child: AppSelect<String>(
                value: _needsRecipe ? 'yes' : 'no',
                items: const [AppSelectItem(value: 'yes', label: 'Yes'), AppSelectItem(value: 'no', label: 'No')],
                onChanged: (v) => setState(() => _needsRecipe = v == 'yes'),
              ),
            ),
          ]),
          const SizedBox(height: 18),
          _footer(context, label: 'Save', busy: _saving, onSave: _save),
        ],
      ),
    );
  }
}

/// "Recipe — {product}": the bill of materials per output unit. Rows with
/// no material or no quantity are dropped on save, as on the web.
class ProductRecipeScreen extends StatefulWidget {
  const ProductRecipeScreen({super.key, required this.session, required this.company, required this.product});
  final Session session;
  final Company company;
  final Map<String, dynamic> product;

  @override
  State<ProductRecipeScreen> createState() => _ProductRecipeScreenState();
}

class _RecipeRow {
  _RecipeRow({this.itemId = '', String qty = '0', String waste = '0', this.optional = false})
      : qty = TextEditingController(text: qty),
        waste = TextEditingController(text: waste);
  String itemId;
  final TextEditingController qty;
  final TextEditingController waste;
  bool optional;
  void dispose() {
    qty.dispose();
    waste.dispose();
  }
}

class _ProductRecipeScreenState extends State<ProductRecipeScreen> {
  final _name = TextEditingController();
  final List<_RecipeRow> _rows = [];
  List<AppSelectItem<String>>? _materials;
  bool _loading = true;
  bool _saving = false;

  Object? get _productId => widget.product['poultryProductId'];
  Map<String, dynamic> get _scope => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final client = widget.session.farmClient;
    try {
      final items = await client.get('/api/Poultry/raw-material-items', query: _scope);
      _materials = [
        for (final it in LookupLoader.rowsIn(items))
          if (it is Map && it['isActive'] != false)
            AppSelectItem(value: '${it['poultryRawMaterialItemId']}', label: '${it['itemName'] ?? ''}'),
      ];
    } catch (_) {
      _materials = const [];
    }
    try {
      final r = await client.get('/api/Poultry/products/$_productId/recipe', query: _scope);
      if (r is Map) {
        _name.text = '${r['recipeName'] ?? ''}';
        for (final it in (r['items'] is List ? r['items'] as List : const [])) {
          if (it is! Map) continue;
          _rows.add(_RecipeRow(
            itemId: '${it['poultryRawMaterialItemId'] ?? ''}',
            qty: _num(it['quantityPerOutputUnit'] ?? 0),
            waste: _num(it['wasteAllowancePercent'] ?? 0),
            optional: it['isOptional'] == true,
          ));
        }
      }
    } on ApiException catch (e) {
      // No recipe yet answers 404 on some builds; anything else is reported.
      if (e.statusCode != 404 && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load recipe. ${e.message}')));
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      final id = int.tryParse(r.itemId) ?? 0;
      final qty = double.tryParse(r.qty.text.trim()) ?? 0;
      if (id == 0 || qty <= 0) continue;
      items.add({
        'poultryRawMaterialItemId': id,
        'quantityPerOutputUnit': qty,
        'wasteAllowancePercent': double.tryParse(r.waste.text.trim()) ?? 0,
        'isOptional': r.optional,
        'displayOrder': i,
      });
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.session.farmClient.put('/api/Poultry/products/$_productId/recipe', body: {
        'farmId': widget.company.farmId,
        'recipeName': _name.text.trim().isEmpty ? null : _name.text.trim(),
        'items': items,
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('Recipe saved')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Save failed. ${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(title: Text('Recipe — ${widget.product['name'] ?? ''}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
              children: [
                FormSection(title: 'Bill of materials (per output unit)', color: SectionColor.indigo, columns: 1, children: [
                  AppField(label: 'Recipe name', full: true,
                      child: AppInput(controller: _name, hintText: 'Optional')),
                  for (var i = 0; i < _rows.length; i++)
                    AppField(
                      label: '',
                      full: true,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: tokens.border),
                          borderRadius: BorderRadius.circular(Dim.radiusMd),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppSelect<String>(
                              value: _rows[i].itemId.isEmpty ? null : _rows[i].itemId,
                              hintText: (_materials?.isEmpty ?? true) ? 'No raw materials yet' : 'Raw material',
                              items: _materials ?? const [],
                              onChanged: (v) => setState(() => _rows[i].itemId = v ?? ''),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: AppField(label: 'Qty per unit',
                                      child: AppNumberInput(controller: _rows[i].qty, allowDecimal: true)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: AppField(label: 'Waste %',
                                      child: AppNumberInput(controller: _rows[i].waste, allowDecimal: true)),
                                ),
                              ],
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                                onPressed: () => setState(() => _rows.removeAt(i).dispose()),
                                icon: const Icon(Icons.delete_outline, size: 18),
                                label: const Text('Remove'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  AppField(
                    label: '',
                    full: true,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton(
                        label: 'Add material',
                        icon: Icons.add,
                        variant: AppButtonVariant.outline,
                        size: AppButtonSize.sm,
                        onPressed: () => setState(() => _rows.add(_RecipeRow())),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 18),
                _footer(context, label: 'Save recipe', busy: _saving, onSave: _save),
              ],
            ),
    );
  }
}

/// "Add stock — {product}": a Restock stock transaction.
class ProductStockScreen extends StatefulWidget {
  const ProductStockScreen({super.key, required this.session, required this.company, required this.product});
  final Session session;
  final Company company;
  final Map<String, dynamic> product;

  @override
  State<ProductStockScreen> createState() => _ProductStockScreenState();
}

class _ProductStockScreenState extends State<ProductStockScreen> {
  final _qty = TextEditingController(text: '0');
  final _cost = TextEditingController(text: '0');
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_qty, _cost, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final qty = double.tryParse(_qty.text.trim()) ?? 0;
    if (qty <= 0) {
      messenger.showSnackBar(const SnackBar(content: Text('Quantity must be greater than 0')));
      return;
    }
    final cost = double.tryParse(_cost.text.trim()) ?? 0;
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Poultry/stock/transactions', body: {
        'farmId': widget.company.farmId,
        'poultryProductId': widget.product['poultryProductId'],
        'txnType': 'Restock',
        'quantity': qty,
        'unitCost': cost == 0 ? null : cost,
        'note': _note.text.trim().isEmpty ? 'Product stock addition' : _note.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('Stock added')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Could not add stock. ${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Add stock — ${widget.product['name'] ?? ''}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          FormSection(title: 'Stock addition', color: SectionColor.emerald, children: [
            AppField(label: 'Quantity', required: true,
                child: AppNumberInput(controller: _qty, allowDecimal: true)),
            AppField(label: 'Unit cost / value',
                child: AppNumberInput(controller: _cost, allowDecimal: true)),
            AppField(label: 'Note', full: true, child: AppInput(controller: _note)),
          ]),
          const SizedBox(height: 18),
          _footer(context, label: 'Add stock', busy: _saving, onSave: _save),
        ],
      ),
    );
  }
}
