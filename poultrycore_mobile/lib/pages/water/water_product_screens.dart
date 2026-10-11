import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/form_section.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../lookup_loader.dart';
import '../poultry/reports/report_format.dart' show FarmMoney;

// Water → Setup → Production → Products, as `app/water-products/page.tsx`
// (the product dialog, Restock, and the post-create recipe nudge) and
// `app/water-products/[id]/page.tsx` (Product Details: Overview, Production
// recipe, Settings). Water's own — nothing here is Poultry's.

/// PRODUCT_TYPES on the list page, with the web's hints.
const _productTypes = <(String, String)>[
  ('FinishedGood', 'Finished good — Sold to customers, e.g. sachet water'),
  ('RawMaterial', 'Raw material — Consumed during production'),
  ('PackagingMaterial', 'Packaging material — Rolls, bags, etc.'),
  ('Consumable', 'Consumable'),
  ('SparePart', 'Spare part'),
  ('Service', 'Service'),
  ('Other', 'Other'),
];

/// PRODUCT_TYPES on the details page's Settings tab: only four.
const _settingsTypes = <(String, String)>[
  ('FinishedGood', 'Finished good'),
  ('RawMaterial', 'Raw material'),
  ('PackagingMaterial', 'Packaging material'),
  ('Other', 'Other'),
];

const _inventoryUnits = ['Sachet', 'Bottle', 'Dispenser Bottle', 'Cup', 'Container', 'Piece', 'Litre', 'Other'];
const _soldIndividually = 'None — Sold individually';
const _packagingUnits = [
  'Bag',
  'Pack',
  'Crate',
  'Carton',
  'Case',
  'Bundle',
  'Tray',
  'Pallet',
  _soldIndividually,
  'Other',
];
const _sizeUnits = ['ml', 'L', 'cl', 'g', 'kg', 'Other'];
const _categories = [
  'Sachet Water',
  'Bottled Water',
  'Dispenser Water',
  'Bulk Water',
  'Packaging Materials',
  'Water Treatment Materials',
  'Cleaning Supplies',
  'Machine Parts',
  'Vehicle Supplies',
  'Other',
];

String _num(Object? v) => v == null ? '' : '$v';
num? _numOrNull(String raw) => raw.trim().isEmpty ? null : num.tryParse(raw.trim());
int? _intOrNull(String raw) => raw.trim().isEmpty ? null : int.tryParse(raw.trim());

/// The web's red Cancel and primary save, side by side.
Widget _footer(BuildContext context, {required String label, required bool busy, required VoidCallback onSave}) {
  return Row(
    children: [
      Expanded(
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: AppButton(
          label: busy ? 'Saving…' : label,
          size: AppButtonSize.lg,
          fullWidth: true,
          busy: busy,
          onPressed: busy ? null : onSave,
        ),
      ),
    ],
  );
}

/// deriveProduct(): fills the legacy columns from Packaging & Pricing so
/// sales, inventory and stock conversion keep working.
Map<String, dynamic> deriveWaterProduct(Map<String, dynamic> f) {
  final perPkg = (f['sachetsPerBag'] as num?) ?? 0;
  final dsu = f['defaultSalesUnit'];
  final unit = f['unit'];
  final sellsByUnit = dsu != null && '$dsu'.isNotEmpty && unit != null && '$unit'.isNotEmpty && dsu == unit;
  final unitPrice = sellsByUnit
      ? (f['sachetPrice'] ?? f['bagPrice'] ?? f['unitPrice'] ?? 0)
      : (f['bagPrice'] ?? f['sachetPrice'] ?? f['unitPrice'] ?? 0);
  return {...f, 'baseUnit': unit, 'isSachetProduct': perPkg > 1, 'unitPrice': unitPrice};
}

// ---------------------------------------------------------------- the form

/// "New water product" / "Edit water product".
class WaterProductFormScreen extends StatefulWidget {
  const WaterProductFormScreen({super.key, required this.session, required this.company, this.existing});
  final Session session;
  final Company company;
  final Map<String, dynamic>? existing;

  @override
  State<WaterProductFormScreen> createState() => _WaterProductFormScreenState();
}

class _WaterProductFormScreenState extends State<WaterProductFormScreen> {
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _size = TextEditingController();
  final _perPkg = TextEditingController(text: '30');
  final _bagPrice = TextEditingController(text: '0');
  final _unitPriceInv = TextEditingController(text: '0');
  final _notes = TextEditingController();
  String _type = 'FinishedGood';
  String _category = 'Sachet Water';
  String _sizeUnit = 'ml';
  String _unit = 'Sachet';
  String _packaging = 'Bag';
  String _salesUnit = 'Bag';
  bool _active = true;
  num _unitPrice = 0;
  bool _saving = false;

  Map<String, dynamic>? get _row => widget.existing;
  bool get _isEdit => _row != null;

  @override
  void initState() {
    super.initState();
    final p = _row;
    if (p == null) return;
    // openEdit()
    _name.text = '${p['name'] ?? ''}';
    _sku.text = '${p['sku'] ?? ''}';
    _size.text = _num(p['sizeMl']);
    _sizeUnit = '${p['sizeUnit'] ?? 'ml'}';
    _unit = '${p['unit'] ?? 'Sachet'}';
    _unitPrice = (p['unitPrice'] as num?) ?? 0;
    _active = p['isActive'] != false;
    _type = '${p['productType'] ?? 'FinishedGood'}';
    _notes.text = '${p['notes'] ?? ''}';
    _packaging = '${p['packagingUnit'] ?? 'Bag'}';
    _perPkg.text = _num(p['sachetsPerBag'] ?? 30);
    _salesUnit = '${p['defaultSalesUnit'] ?? p['packagingUnit'] ?? 'Bag'}';
    _bagPrice.text = _num(p['bagPrice'] ?? 0);
    _unitPriceInv.text = _num(p['sachetPrice'] ?? 0);
    _category = '${p['productCategory'] ?? ''}';
  }

  @override
  void dispose() {
    for (final c in [_name, _sku, _size, _perPkg, _bagPrice, _unitPriceInv, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// "Units per Bag *" — the package word follows the packaging unit.
  String get _pkg => _packaging.isNotEmpty && _packaging != _soldIndividually ? _packaging : 'Package';
  String get _inv => _unit.isNotEmpty ? _unit : 'Unit';

  List<String> get _salesUnitOptions => {
    for (final u in [_unit, _packaging])
      if (u.isNotEmpty && u != _soldIndividually) u,
  }.toList();

  Map<String, dynamic> _form() {
    final size = _intOrNull(_size.text);
    return {
      'name': _name.text,
      'sku': _sku.text,
      // undefined in the web's form state, so JSON leaves it out.
      'sizeMl': ?size,
      'sizeUnit': _sizeUnit,
      'unit': _unit,
      'unitPrice': _unitPrice,
      'isActive': _active,
      'productType': _type,
      'notes': _notes.text,
      'packagingUnit': _packaging,
      'sachetsPerBag': _intOrNull(_perPkg.text),
      'defaultSalesUnit': _salesUnit,
      'bagPrice': _numOrNull(_bagPrice.text),
      'sachetPrice': _numOrNull(_unitPriceInv.text),
      'productCategory': _category,
      'isSachetProduct': _isEdit ? _row!['isSachetProduct'] == true : true,
    };
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_name.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Name required')));
      return;
    }
    setState(() => _saving = true);
    final client = widget.session.farmClient;
    final body = {...deriveWaterProduct(_form()), 'farmId': widget.company.farmId};
    try {
      if (_isEdit) {
        final id = _row!['waterProductId'];
        await client.put('/api/Water/products/$id', body: {...body, 'waterProductId': id});
        if (!mounted) return;
        Navigator.of(context).pop(true);
        messenger.showSnackBar(const SnackBar(content: Text('Product updated')));
        return;
      }
      final created = await client.post('/api/Water/products', body: body);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Product created')));
      // The recipe nudge, for finished goods only: raw and packaging
      // materials ARE the recipe ingredients.
      final newId = created is Map ? created['waterProductId'] : null;
      if (_type == 'FinishedGood' && newId != null) {
        setState(() => _saving = false);
        final addRecipe = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.restaurant_menu, color: Color(0xFF0284C7)),
                SizedBox(width: 8),
                Expanded(child: Text('Product created successfully')),
              ],
            ),
            content: Text(
              'Do you want to set up the production recipe for ${created['name'] ?? _name.text.trim()} now? '
              'The recipe tells the app which raw materials are used to produce one bag, so production records auto-load them.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add recipe')),
            ],
          ),
        );
        if (!mounted) return;
        if (addRecipe == true) {
          Navigator.of(context).pushReplacement<void, bool>(
            MaterialPageRoute(
              builder: (_) => WaterProductDetailsScreen(
                session: widget.session,
                company: widget.company,
                productId: int.tryParse('$newId') ?? 0,
              ),
            ),
            result: true,
          );
          return;
        }
      }
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('${_isEdit ? 'Update' : 'Create'} failed. ${e.message}')));
    }
  }

  AppSelect<String> _select(
    String? value,
    List<String> options,
    ValueChanged<String> onChanged, {
    String hint = 'Select…',
  }) {
    return AppSelect<String>(
      value: value != null && options.contains(value) ? value : null,
      hintText: hint,
      items: [for (final o in options) AppSelectItem(value: o, label: o)],
      onChanged: (v) => setState(() => onChanged(v ?? '')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final salesOptions = _salesUnitOptions;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEdit ? 'Edit water product' : 'New water product',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              _isEdit ? 'Update the product details below' : 'Add a new product to your catalog',
              style: TextStyle(fontSize: 11.5, color: tokens.mutedForeground),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          FormSection(
            title: 'Basics',
            color: SectionColor.indigo,
            children: [
              AppField(
                label: 'Name',
                required: true,
                full: true,
                child: AppInput(controller: _name),
              ),
              AppField(
                label: 'Product type',
                full: true,
                child: AppSelect<String>(
                  value: _type,
                  items: [
                    for (final (v, l) in _productTypes) AppSelectItem(value: v, label: l),
                    // A type saved before this list existed still shows.
                    if (!_productTypes.any((t) => t.$1 == _type)) AppSelectItem(value: _type, label: _type),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
              ),
              AppField(
                label: 'SKU',
                child: AppInput(controller: _sku),
              ),
              AppField(label: 'Product category', child: _select(_category, _categories, (v) => _category = v)),
            ],
          ),
          const SizedBox(height: 12),
          FormSection(
            title: 'Packaging & Pricing',
            color: SectionColor.blue,
            children: [
              AppField(
                label: 'Size per unit',
                child: Row(
                  children: [
                    Expanded(child: AppNumberInput(controller: _size)),
                    const SizedBox(width: 8),
                    SizedBox(width: 96, child: _select(_sizeUnit, _sizeUnits, (v) => _sizeUnit = v)),
                  ],
                ),
              ),
              AppField(
                label: 'Inventory unit',
                required: true,
                child: _select(_unit, _inventoryUnits, (v) {
                  _unit = v;
                  if (_salesUnit.isEmpty) _salesUnit = v;
                }),
              ),
              AppField(
                label: 'Packaging unit',
                required: true,
                child: _select(_packaging, _packagingUnits, (v) {
                  _packaging = v;
                  if (_salesUnit.isEmpty) _salesUnit = v;
                }),
              ),
              AppField(
                label: 'Units per $_pkg',
                required: true,
                child: AppNumberInput(controller: _perPkg),
              ),
              AppField(
                label: 'Default sales unit',
                required: true,
                child: _select(
                  _salesUnit,
                  salesOptions,
                  (v) => _salesUnit = v,
                  hint: salesOptions.isEmpty ? 'Pick inventory / packaging unit first.' : 'Select…',
                ),
              ),
              AppField(
                label: 'Selling price per $_pkg',
                required: true,
                child: AppNumberInput(controller: _bagPrice, allowDecimal: true),
              ),
              AppField(
                label: 'Selling price per $_inv',
                child: AppNumberInput(controller: _unitPriceInv, allowDecimal: true),
              ),
              AppField(
                label: 'Active',
                full: true,
                child: AppCheckbox(
                  value: _active,
                  label: 'Active (visible in sales)',
                  onChanged: (v) => setState(() => _active = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FormSection(
            title: 'Notes',
            color: SectionColor.green,
            columns: 1,
            children: [
              AppField(
                label: 'Notes',
                full: true,
                child: AppInput(controller: _notes),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _footer(context, label: 'Save', busy: _saving, onSave: _save),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- restock

/// "Add stock — {product}": a Restock stock transaction.
class WaterProductStockScreen extends StatefulWidget {
  const WaterProductStockScreen({super.key, required this.session, required this.company, required this.product});
  final Session session;
  final Company company;
  final Map<String, dynamic> product;

  @override
  State<WaterProductStockScreen> createState() => _WaterProductStockScreenState();
}

class _WaterProductStockScreenState extends State<WaterProductStockScreen> {
  final _qty = TextEditingController();
  final _cost = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final qty = int.tryParse(_qty.text.trim()) ?? 0;
    if (qty <= 0) {
      messenger.showSnackBar(const SnackBar(content: Text('Enter a positive quantity')));
      return;
    }
    setState(() => _saving = true);
    final me = widget.session.tokens.userId ?? '';
    try {
      await widget.session.farmClient.post(
        '/api/Water/stock/transactions',
        body: {
          'waterProductId': widget.product['waterProductId'],
          'txnType': 'Restock',
          'quantity': qty,
          'unitCost': _numOrNull(_cost.text),
          'note': 'Restocked $qty',
          'farmId': widget.company.farmId,
          'createdBy': me.isEmpty ? null : me,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('Stock added')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Restock failed. ${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add stock — ${widget.product['name'] ?? ''}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text('Record a restock for this product', style: TextStyle(fontSize: 11.5, color: tokens.mutedForeground)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          FormSection(
            title: 'Restock',
            color: SectionColor.blue,
            children: [
              AppField(
                label: 'Quantity',
                child: AppNumberInput(controller: _qty),
              ),
              AppField(
                label: 'Unit cost (optional)',
                child: AppNumberInput(controller: _cost, allowDecimal: true),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _footer(context, label: 'Add stock', busy: _saving, onSave: _save),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- details

class _RecipeRow {
  _RecipeRow({
    required this.itemId,
    num qty = 0,
    this.unit = 'bag',
    num waste = 0,
    this.optional = false,
    this.notes = '',
  }) : qty = TextEditingController(text: _num(qty)),
       unitCtl = TextEditingController(text: unit),
       waste = TextEditingController(text: _num(waste));
  int itemId;
  final TextEditingController qty;
  final String unit;
  final TextEditingController unitCtl;
  final TextEditingController waste;
  bool optional;
  final String notes;
  void dispose() {
    qty.dispose();
    unitCtl.dispose();
    waste.dispose();
  }
}

/// Product Details: title, four stat cards, and Overview / Production recipe
/// / Settings tabs.
class WaterProductDetailsScreen extends StatefulWidget {
  const WaterProductDetailsScreen({super.key, required this.session, required this.company, required this.productId});
  final Session session;
  final Company company;
  final int productId;

  @override
  State<WaterProductDetailsScreen> createState() => _WaterProductDetailsScreenState();
}

class _WaterProductDetailsScreenState extends State<WaterProductDetailsScreen> {
  Map<String, dynamic>? _product;
  List<Map<String, dynamic>> _materials = const [];
  Map<String, dynamic>? _recipe;
  final List<_RecipeRow> _rows = [];
  FarmMoney _money = const FarmMoney();
  bool _loading = true;
  bool _savingRecipe = false;
  bool _savingSettings = false;

  // Settings tab.
  final _sName = TextEditingController();
  final _sSku = TextEditingController();
  final _sUnit = TextEditingController();
  final _sSize = TextEditingController();
  final _sPrice = TextEditingController();
  final _sNotes = TextEditingController();
  final _sPerBag = TextEditingController();
  final _sBagPrice = TextEditingController();
  final _sSachetPrice = TextEditingController();
  String _sType = 'FinishedGood';
  bool _sSachet = false;
  String? _sBaseUnit;
  bool _sActive = true;

  Map<String, dynamic> get _scope => {'farmId': widget.company.farmId};
  String get _base => '/api/Water/products/${widget.productId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    for (final c in [_sName, _sSku, _sUnit, _sSize, _sPrice, _sNotes, _sPerBag, _sBagPrice, _sSachetPrice]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _load() async {
    final client = widget.session.farmClient;
    setState(() => _loading = true);
    try {
      _money = await FarmMoney.load(widget.session, widget.company);
      final p = await client.get(_base, query: _scope);
      final mats = await client.get('/api/Water/raw-material-items', query: _scope);
      Object? r;
      try {
        // Fetched for every type, so flipping to Finished good has the data.
        r = await client.get('$_base/recipe', query: _scope);
      } catch (_) {
        r = null;
      }
      if (!mounted) return;
      setState(() {
        _product = p is Map ? Map<String, dynamic>.from(p) : null;
        _materials = [
          for (final m in LookupLoader.rowsIn(mats))
            if (m is Map) Map<String, dynamic>.from(m),
        ];
        _recipe = r is Map ? Map<String, dynamic>.from(r) : null;
        for (final x in _rows) {
          x.dispose();
        }
        _rows
          ..clear()
          ..addAll([
            for (final it in (_recipe?['items'] is List ? _recipe!['items'] as List : const []))
              if (it is Map)
                _RecipeRow(
                  itemId: int.tryParse('${it['waterRawMaterialItemId']}') ?? 0,
                  qty: (it['quantityPerOutputUnit'] as num?) ?? 0,
                  unit: '${it['outputUnit'] ?? 'bag'}',
                  waste: (it['wasteAllowancePercent'] as num?) ?? 0,
                  optional: it['isOptional'] == true,
                  notes: '${it['notes'] ?? ''}',
                ),
          ]);
        final pr = _product;
        if (pr != null) {
          _sName.text = '${pr['name'] ?? ''}';
          _sSku.text = '${pr['sku'] ?? ''}';
          _sUnit.text = '${pr['unit'] ?? ''}';
          _sSize.text = _num(pr['sizeMl']);
          _sPrice.text = _num(pr['unitPrice'] ?? 0);
          _sNotes.text = '${pr['notes'] ?? ''}';
          _sType = '${pr['productType'] ?? 'FinishedGood'}';
          _sActive = pr['isActive'] != false;
          _sBaseUnit = pr['baseUnit'] as String?;
          _sPerBag.text = _num(pr['sachetsPerBag']);
          _sBagPrice.text = _num(pr['bagPrice']);
          _sSachetPrice.text = _num(pr['sachetPrice']);
          _sSachet = pr['isSachetProduct'] == true;
        }
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Could not load product. ${e.message}');
    }
  }

  bool get _isFinishedGood => _sType == 'FinishedGood';

  /// Active materials, by name.
  List<Map<String, dynamic>> get _picker => [
    for (final m in _materials)
      if (m['isActive'] != false) m,
  ]..sort((a, b) => '${a['itemName'] ?? ''}'.compareTo('${b['itemName'] ?? ''}'));

  void _addRow() {
    final used = {for (final r in _rows) r.itemId};
    final next = _picker.where((m) => !used.contains(int.tryParse('${m['waterRawMaterialItemId']}'))).firstOrNull;
    if (next == null) {
      _snack('No raw materials left to add. Create more raw materials first.');
      return;
    }
    setState(() => _rows.add(_RecipeRow(itemId: int.tryParse('${next['waterRawMaterialItemId']}') ?? 0)));
  }

  Future<void> _saveRecipe() async {
    if (!_isFinishedGood) {
      return _snack("Only finished goods can have recipes. Change Product type to 'Finished good' in Settings first.");
    }
    final seen = <int>{};
    for (final r in _rows) {
      if (!seen.add(r.itemId)) return _snack('Duplicate material. Each raw material can appear once.');
      if ((num.tryParse(r.qty.text.trim()) ?? 0) < 0) return _snack('Quantity cannot be negative');
    }
    setState(() => _savingRecipe = true);
    final me = widget.session.tokens.userId ?? '';
    try {
      await widget.session.farmClient.put(
        '$_base/recipe',
        query: {..._scope, 'updatedBy': me},
        body: {
          'recipeName': _recipe?['recipeName'] ?? 'Default',
          'notes': _recipe?['notes'],
          'items': [
            for (var i = 0; i < _rows.length; i++)
              {
                'waterRawMaterialItemId': _rows[i].itemId,
                'quantityPerOutputUnit': num.tryParse(_rows[i].qty.text.trim()) ?? 0,
                'outputUnit': _rows[i].unitCtl.text.isEmpty ? 'bag' : _rows[i].unitCtl.text,
                'wasteAllowancePercent': num.tryParse(_rows[i].waste.text.trim()) ?? 0,
                'isOptional': _rows[i].optional,
                'displayOrder': i,
                'notes': _rows[i].notes.isEmpty ? null : _rows[i].notes,
              },
          ],
        },
      );
      if (!mounted) return;
      _snack('Recipe saved');
      await _load();
    } on ApiException catch (e) {
      if (mounted) _snack('Save failed. ${e.message}');
    }
    if (mounted) setState(() => _savingRecipe = false);
  }

  Future<void> _saveSettings() async {
    if (_sName.text.trim().isEmpty) return _snack('Name required');
    setState(() => _savingSettings = true);
    final size = _intOrNull(_sSize.text);
    // The Settings form's own fields only, as the web sends settingsForm.
    final body = {
      'name': _sName.text,
      'sku': _sSku.text,
      'sizeMl': ?size,
      'unit': _sUnit.text,
      'unitPrice': num.tryParse(_sPrice.text.trim()) ?? 0,
      'isActive': _sActive,
      'productType': _sType,
      'notes': _sNotes.text,
      'baseUnit': _sBaseUnit,
      'sachetsPerBag': _intOrNull(_sPerBag.text),
      'bagPrice': _numOrNull(_sBagPrice.text),
      'sachetPrice': _numOrNull(_sSachetPrice.text),
      'isSachetProduct': _sSachet,
      'waterProductId': widget.productId,
      'farmId': widget.company.farmId,
    };
    try {
      await widget.session.farmClient.put(_base, body: body);
      if (!mounted) return;
      _snack('Product updated');
      await _load();
    } on ApiException catch (e) {
      if (mounted) _snack('Save failed. ${e.message}');
    }
    if (mounted) setState(() => _savingSettings = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(title: const Text('Back')),
        body: _loading
            ? const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Loading product…'),
                  ],
                ),
              )
            : p == null
            ? const Center(child: Text('Product not found.'))
            : NestedScrollView(
                headerSliverBuilder: (context, _) => [
                  SliverToBoxAdapter(child: _header(context, p)),
                  SliverToBoxAdapter(
                    child: TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: const [
                        Tab(text: 'Overview'),
                        Tab(text: 'Production recipe'),
                        Tab(text: 'Settings'),
                      ],
                    ),
                  ),
                ],
                body: TabBarView(children: [_overview(context, p), _recipeTab(context), _settingsTab(context)]),
              ),
      ),
    );
  }

  Widget _header(BuildContext context, Map<String, dynamic> p) {
    final tokens = context.tokens;
    final stock = (p['stockOnHand'] as num?) ?? 0;
    Widget stat(String label, Widget value) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.card,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(Dim.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
          const SizedBox(height: 2),
          DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            child: value,
          ),
        ],
      ),
    );
    final meta = [
      if ('${p['sku'] ?? ''}'.isNotEmpty) 'SKU ${p['sku']}',
      if ('${p['unit'] ?? ''}'.isNotEmpty) '· ${p['unit']}',
      if (p['sizeMl'] != null && p['sizeMl'] != 0) '· ${p['sizeMl']} ml',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.shopping_bag_outlined, color: Color(0xFF0284C7), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${p['name'] ?? ''}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            border: Border.all(color: tokens.border),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${p['productType'] ?? ''}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                        for (final m in meta) Text(m, style: TextStyle(fontSize: 12.5, color: tokens.mutedForeground)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final w in [
                  stat('Unit price', Text(_money((p['unitPrice'] as num?) ?? 0))),
                  stat('Stock on hand', Text(fixedInt(stock))),
                  stat(
                    'Status',
                    p['isActive'] != false
                        ? const Text('Active', style: TextStyle(color: Color(0xFF059669)))
                        : const Text('Inactive', style: TextStyle(color: Color(0xFF94A3B8))),
                  ),
                  stat('Recipe items', Text('${_rows.length}')),
                ])
                  SizedBox(width: (c.maxWidth - 10) / 2, child: w),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Widget child) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.card,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(Dim.radiusMd),
      ),
      child: child,
    );
  }

  Widget _overview(BuildContext context, Map<String, dynamic> p) {
    final tokens = context.tokens;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 14, color: tokens.mutedForeground)),
          ),
          Expanded(flex: 2, child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
    String dash(Object? v) => v == null || '$v'.isEmpty ? '—' : '$v';
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _card(
          context,
          Column(
            children: [
              row('Name', '${p['name'] ?? ''}'),
              row('Product type', '${p['productType'] ?? ''}'),
              row('SKU', dash(p['sku'])),
              row('Unit', dash(p['unit'])),
              row('Size', p['sizeMl'] != null && p['sizeMl'] != 0 ? '${p['sizeMl']} ml' : '—'),
              row('Unit price', _money((p['unitPrice'] as num?) ?? 0)),
              row('Stock on hand', fixedInt((p['stockOnHand'] as num?) ?? 0)),
              row('Active', p['isActive'] != false ? 'Yes' : 'No'),
              row('Notes', dash(p['notes'])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _recipeTab(BuildContext context) {
    final tokens = context.tokens;
    final picker = _picker;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (!_isFinishedGood)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              border: Border.all(color: const Color(0xFFFDE68A)),
              borderRadius: BorderRadius.circular(Dim.radiusMd),
            ),
            child: const Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 13.5, color: Color(0xFF78350F)),
                children: [
                  TextSpan(text: 'Recipes only apply to finished goods. Change the product type to'),
                  TextSpan(
                    text: ' Finished good',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: ' in'),
                  TextSpan(
                    text: ' Settings',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: ' to use this tab.'),
                ],
              ),
            ),
          ),
        _card(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Production recipe', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text(
                'What raw materials are needed per output unit (typically per bag).',
                style: TextStyle(fontSize: 12, color: tokens.mutedForeground),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppButton(
                    label: 'Add material',
                    icon: Icons.add,
                    variant: AppButtonVariant.outline,
                    size: AppButtonSize.sm,
                    onPressed: _isFinishedGood ? _addRow : null,
                  ),
                  AppButton(
                    label: _savingRecipe ? 'Saving…' : 'Save recipe',
                    icon: Icons.save_outlined,
                    size: AppButtonSize.sm,
                    onPressed: _savingRecipe || !_isFinishedGood ? null : _saveRecipe,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text.rich(
                    textAlign: TextAlign.center,
                    TextSpan(
                      style: TextStyle(fontSize: 13.5, color: tokens.mutedForeground),
                      children: const [
                        TextSpan(text: 'No materials in this recipe yet. Click '),
                        TextSpan(
                          text: 'Add material',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: ' to start.'),
                      ],
                    ),
                  ),
                )
              else
                for (var i = 0; i < _rows.length; i++) _recipeRow(context, i, picker),
            ],
          ),
        ),
      ],
    );
  }

  Widget _recipeRow(BuildContext context, int i, List<Map<String, dynamic>> picker) {
    final tokens = context.tokens;
    final r = _rows[i];
    final mat = _materials.where((m) => int.tryParse('${m['waterRawMaterialItemId']}') == r.itemId).firstOrNull;
    final stock = mat == null
        ? '—'
        : '${fmtNumLocale((mat['currentQuantity'] as num?) ?? 0)} ${mat['unitOfMeasure'] ?? ''}'.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(Dim.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppField(
            label: 'Raw material',
            child: AppSelect<int>(
              value: picker.any((m) => int.tryParse('${m['waterRawMaterialItemId']}') == r.itemId) ? r.itemId : null,
              items: [
                for (final m in picker)
                  AppSelectItem(
                    value: int.tryParse('${m['waterRawMaterialItemId']}') ?? 0,
                    label: '${m['itemName'] ?? ''} (${m['unitOfMeasure'] ?? '—'})',
                  ),
              ],
              onChanged: (v) => setState(() => r.itemId = v ?? r.itemId),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppField(
                  label: 'Qty / output',
                  child: AppNumberInput(controller: r.qty, allowDecimal: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppField(
                  label: 'Per (unit)',
                  child: AppInput(controller: r.unitCtl),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppField(
                  label: 'Waste %',
                  child: AppNumberInput(controller: r.waste, allowDecimal: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: AppCheckbox(
                  value: r.optional,
                  label: 'Optional',
                  onChanged: (v) => setState(() => r.optional = v),
                ),
              ),
              Text('Stock: $stock', style: TextStyle(fontSize: 12.5, color: tokens.mutedForeground)),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                onPressed: () => setState(() => _rows.removeAt(i).dispose()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _settingsTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _card(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppField(
                label: 'Name',
                required: true,
                child: AppInput(controller: _sName),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppField(
                      label: 'Product type',
                      child: AppSelect<String>(
                        value: _sType,
                        items: [
                          for (final (v, l) in _settingsTypes) AppSelectItem(value: v, label: l),
                          if (!_settingsTypes.any((t) => t.$1 == _sType)) AppSelectItem(value: _sType, label: _sType),
                        ],
                        onChanged: (v) => setState(() => _sType = v ?? _sType),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppField(
                      label: 'SKU',
                      child: AppInput(controller: _sSku),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppField(
                      label: 'Unit',
                      child: AppInput(controller: _sUnit, hintText: 'sachet / bottle / gallon'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppField(
                      label: 'Size (ml)',
                      child: AppNumberInput(controller: _sSize),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              AppField(
                label: 'Unit price',
                required: true,
                child: AppNumberInput(controller: _sPrice, allowDecimal: true),
              ),
              const SizedBox(height: 10),
              AppField(
                label: 'Notes',
                child: AppTextarea(controller: _sNotes),
              ),
              const Divider(height: 24),
              AppCheckbox(
                value: _sSachet,
                label: 'Sachet product — sells by Bag or Sachet',
                onChanged: (v) => setState(() {
                  _sSachet = v;
                  _sBaseUnit = v ? (_sBaseUnit ?? 'Sachet') : null;
                }),
              ),
              if (_sSachet) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppField(
                        label: 'Sachets per bag',
                        child: AppNumberInput(controller: _sPerBag),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppField(
                        label: 'Bag price',
                        child: AppNumberInput(controller: _sBagPrice, allowDecimal: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppField(
                        label: 'Sachet price',
                        child: AppNumberInput(controller: _sSachetPrice, allowDecimal: true),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              AppCheckbox(
                value: _sActive,
                label: 'Active (visible in sales)',
                onChanged: (v) => setState(() => _sActive = v),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: AppButton(
                  label: _savingSettings ? 'Saving…' : 'Save settings',
                  onPressed: _savingSettings ? null : _saveSettings,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// toLocaleString for a whole number: "1,234".
String fixedInt(num n) => fmtNumLocale(n.round());

/// toLocaleString: thousands separators, decimals only when present.
String fmtNumLocale(num n) {
  final neg = n < 0;
  final parts = n.abs().toString().split('.');
  final whole = parts[0];
  final b = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
    b.write(whole[i]);
  }
  final frac = parts.length > 1 && parts[1] != '0' ? '.${parts[1]}' : '';
  return '${neg ? '-' : ''}$b$frac';
}
