// Generic → Catalog → Products, as `app/generic-products/page.tsx`: the
// products or items the business sells, with their prices, opening stock and
// low-stock alert. "Track inventory" off for services.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart';
import '../poultry/sales/balances_widgets.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import 'generic_kit.dart';
import 'reports/generic_report_kit.dart' show fmtMoney;

/// Section bands of the web's FormSection colours.
const genericBandIndigo = Color(0xFF4F46E5);
const genericBandBlue = Color(0xFF2563EB);
const genericBandAmber = Color(0xFFD97706);
const genericBandSlate = Color(0xFF475569);

/// `toLocaleString(undefined, { maximumFractionDigits: 3 })`.
String genericQty(Object? n) {
  final v = tNum(n);
  final s = v.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  final parts = s.split('.');
  final whole = parts.first.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  return parts.length > 1 ? '$whole.${parts[1]}' : whole;
}

/// The page's search: name, SKU or category.
List<Map> filterGenericProducts(List<Map> rows, String search) {
  final q = search.trim().toLowerCase();
  if (q.isEmpty) return rows;
  return rows.where((p) => ['productName', 'sku', 'categoryName'].any((k) => tStr(p[k]).toLowerCase().contains(q))).toList();
}

/// The trailing badge: Inactive, Low stock (tracked and at or under the alert), or OK.
Widget genericProductBadge(Map p) {
  if (p['isActive'] != true) return const TBadge('Inactive', bg: TColors.slate100, fg: TColors.slate900);
  final low = p['trackInventory'] == true && tNum(p['currentStock']) <= tNum(p['minimumStockAlert']);
  return low
      ? const TBadge('Low stock', bg: TColors.rose100, fg: Color(0xFF9F1239))
      : const TBadge('OK', bg: Color(0xFFD1FAE5), fg: Color(0xFF065F46));
}

class GenericProductsScreen extends StatefulWidget {
  const GenericProductsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<GenericProductsScreen> createState() => _GenericProductsScreenState();
}

class _GenericProductsScreenState extends State<GenericProductsScreen> {
  List<Map> _rows = [];
  bool _loading = true;
  final _search = TextEditingController();

  ApiClient get _api => widget.session.farmClient;
  String get _base => genericBase(widget.company);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = rowsOf(await _api.get('$_base/products'));
      if (mounted) setState(() => _rows = r);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load products', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openForm([Map? editing]) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => GenericProductFormDialog(session: widget.session, company: widget.company, editing: editing),
    );
    if (done == true) _load();
  }

  Future<void> _delete(Map p) async {
    final name = tStr(p['productName']);
    final ok = await confirmDelete(
      context,
      title: 'Delete product?',
      description: p['trackInventory'] == true && tNum(p['currentStock']) > 0
          ? '"$name" has ${tNum(p['currentStock'])} units in stock. Backend will refuse if it\'s tied to sales or purchases — deactivate from the edit form to hide instead.'
          : 'Are you sure you want to delete "$name"? This action cannot be undone.',
    );
    if (!ok) return;
    try {
      await _api.delete('$_base/products/${tIntOrNull(p['genericProductId'])}');
      if (mounted) trackerToast(context, 'Product deleted');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Delete failed', description: e.message, error: true);
    }
  }

  String _stock(Map p) => p['trackInventory'] == true ? genericQty(p['currentStock']) : 'n/a';

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/generic-products');
    final visible = filterGenericProducts(_rows, _search.text);
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Products')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.shopping_bag_outlined, size: 24, color: genericEmerald),
              SizedBox(width: 8),
              Expanded(child: Text('Products', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            Text('${_rows.length} product(s)', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: () => _openForm(), icon: const Icon(Icons.add, size: 18), label: const Text('New product')),
            const SizedBox(height: 14),
            if (_loading)
              const LoadingLine('Loading…')
            else if (_rows.isEmpty)
              const _EmptyCard('No products yet. Create your first one.')
            else ...[
              ListFiltersCard(
                search: _search,
                searchPlaceholder: 'Search by name, SKU or category',
                searchOnly: true,
                onSearch: () => setState(() {}),
                from: '',
                to: '',
                onDates: (_, _) {},
                onClear: () => setState(_search.clear),
              ),
              const SizedBox(height: 14),
              MobileCardList<Map>(
                items: visible,
                keyOf: (p) => '${tIntOrNull(p['genericProductId'])}',
                primary: (p) => tStr(p['productName']),
                secondary: (p) => [tStr(p['sku']), tStr(p['unitOfMeasure'])].where((x) => x.isNotEmpty).join(' · '),
                trailing: (p) => Padding(padding: const EdgeInsets.only(left: 6), child: genericProductBadge(p)),
                details: (p) => [
                  ('SKU', tStr(p['sku']).isEmpty ? '—' : tStr(p['sku'])),
                  ('Category', tStr(p['categoryName']).isEmpty ? '—' : tStr(p['categoryName'])),
                  ('Cost', fmtMoney(p['costPrice'])),
                  ('Selling', fmtMoney(p['sellingPrice'])),
                  ('Stock', _stock(p)),
                ],
                actions: (p) => [
                  OutlinedButton.icon(onPressed: () => _openForm(p), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
                  OutlinedButton.icon(
                    onPressed: () => _delete(p),
                    style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: TColors.red200)),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Delete'),
                  ),
                ],
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Name', width: 170), TCol('SKU', width: 100), TCol('Category', width: 120), TCol('Cost', right: true, width: 110),
                    TCol('Selling', right: true, width: 110), TCol('Stock', right: true, width: 90), TCol('Status', width: 100), TCol('', right: true, width: 100),
                  ],
                  rows: [
                    for (final p in items)
                      [
                        Text(tStr(p['productName']), style: const TextStyle(fontWeight: FontWeight.w500)),
                        cellText(tStr(p['sku']).isEmpty ? '—' : tStr(p['sku'])),
                        cellText(tStr(p['categoryName']).isEmpty ? '—' : tStr(p['categoryName'])),
                        Align(alignment: Alignment.centerRight, child: Text(fmtMoney(p['costPrice']))),
                        Align(alignment: Alignment.centerRight, child: Text(fmtMoney(p['sellingPrice']))),
                        Align(alignment: Alignment.centerRight, child: Text(_stock(p))),
                        Align(alignment: Alignment.centerLeft, child: genericProductBadge(p)),
                        Wrap(alignment: WrapAlignment.end, children: [
                          IconButton(tooltip: 'Edit', onPressed: () => _openForm(p), icon: const Icon(Icons.edit_outlined, size: 18)),
                          IconButton(tooltip: 'Delete', onPressed: () => _delete(p), icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600)),
                        ]),
                      ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(this.text, {this.child});
  final String text;
  final Widget? child;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: child ?? Text(text, textAlign: TextAlign.center, style: const TextStyle(color: TColors.slate500)),
      );
}

/// A card with centred grey text: the Catalog pages' empty and status states.
Widget genericEmptyCard(String text, {Widget? child}) => _EmptyCard(text, child: child);

/// New product / Edit product.
class GenericProductFormDialog extends StatefulWidget {
  const GenericProductFormDialog({super.key, required this.session, required this.company, this.editing});
  final Session session;
  final Company company;
  final Map? editing;

  @override
  State<GenericProductFormDialog> createState() => _GenericProductFormDialogState();
}

class _GenericProductFormDialogState extends State<GenericProductFormDialog> {
  late final Map? _e = widget.editing;
  late final _name = TextEditingController(text: tStr(_e?['productName']));
  late final _sku = TextEditingController(text: tStr(_e?['sku']));
  late final _barcode = TextEditingController(text: tStr(_e?['barcode']));
  late final _unit = TextEditingController(text: tStr(_e?['unitOfMeasure']));
  late final _cost = TextEditingController(text: _e == null ? '0' : tStr(_e['costPrice']));
  late final _selling = TextEditingController(text: _e == null ? '0' : tStr(_e['sellingPrice']));
  late final _wholesale = TextEditingController(text: tStr(_e?['wholesalePrice']));
  late final _retail = TextEditingController(text: tStr(_e?['retailPrice']));
  late final _opening = TextEditingController(text: _e == null ? '0' : tStr(_e['openingStock']));
  late final _minAlert = TextEditingController(text: _e == null ? '0' : tStr(_e['minimumStockAlert']));
  late final _notes = TextEditingController(text: tStr(_e?['notes']));
  late bool _track = _e == null ? true : _e['trackInventory'] == true;
  late bool _active = _e == null ? true : _e['isActive'] == true;
  bool _saving = false;

  int? get _editId => tIntOrNull(_e?['genericProductId']);

  @override
  void dispose() {
    for (final c in [_name, _sku, _barcode, _unit, _cost, _selling, _wholesale, _retail, _opening, _minAlert, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return trackerToast(context, 'Product name is required', error: true);
    final cost = num.tryParse(_cost.text.trim().isEmpty ? '0' : _cost.text.trim());
    final sell = num.tryParse(_selling.text.trim().isEmpty ? '0' : _selling.text.trim());
    if (cost == null || cost < 0) return trackerToast(context, 'Cost price must be 0 or more', error: true);
    if (sell == null || sell < 0) return trackerToast(context, 'Selling price must be 0 or more', error: true);
    num? opt(TextEditingController c) => c.text.trim().isEmpty ? null : num.tryParse(c.text.trim());
    String? optStr(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final input = {
      'productName': _name.text.trim(),
      'sku': optStr(_sku),
      'barcode': optStr(_barcode),
      'unitOfMeasure': optStr(_unit),
      'costPrice': cost,
      'sellingPrice': sell,
      'wholesalePrice': opt(_wholesale),
      'retailPrice': opt(_retail),
      'openingStock': num.tryParse(_opening.text.trim()) ?? 0,
      'minimumStockAlert': num.tryParse(_minAlert.text.trim()) ?? 0,
      'trackInventory': _track,
      'isActive': _active,
      'notes': optStr(_notes),
    };
    setState(() => _saving = true);
    final api = widget.session.farmClient;
    final base = genericBase(widget.company);
    try {
      if (_editId != null) {
        await api.put('$base/products/$_editId', body: input);
        if (mounted) trackerToast(context, 'Product updated.');
      } else {
        final created = await api.post('$base/products', body: {...input, 'farmId': widget.company.farmId});
        if (mounted && created is Map) trackerToast(context, 'Product "${tStr(created['productName'])}" created.');
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, _editId != null ? 'Could not save changes' : 'Could not create product', description: e.message, error: true);
    }
  }

  Widget _text(String label, TextEditingController c, int max) =>
      FilterLabel(label, AppInput(controller: c, inputFormatters: [LengthLimitingTextInputFormatter(max)]));

  Widget _num(String label, TextEditingController c) => FilterLabel(
        label,
        AppInput(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final editing = _editId != null;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Row(children: [
          Icon(editing ? Icons.edit_outlined : Icons.add, size: 20, color: genericEmerald),
          const SizedBox(width: 8),
          Expanded(child: Text(editing ? 'Edit product' : 'New product')),
        ]),
        content: SizedBox(
          width: 640,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              'Add a product or item your business sells. Turn off "Track inventory" for services or items you don\'t count stock for.',
              style: TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            formSection('Basics', genericBandIndigo, [
              _text('Product name *', _name, 200),
              _text('SKU (code)', _sku, 60),
              _text('Barcode', _barcode, 60),
              _text('Unit (e.g. piece, kg)', _unit, 30),
            ]),
            const SizedBox(height: 12),
            formSection('Pricing', genericBandBlue, [
              _num('Cost price *', _cost),
              _num('Selling price *', _selling),
              _num('Wholesale price (optional)', _wholesale),
              _num('Retail price (optional)', _retail),
            ]),
            const SizedBox(height: 12),
            formSection('Inventory', genericBandAmber, [
              _num('Opening stock', _opening),
              _num('Low-stock alert at', _minAlert),
            ]),
            const SizedBox(height: 12),
            formSection('Status & notes', genericBandSlate, [
              AppSwitchRow(
                value: _track,
                onChanged: (v) => setState(() => _track = v),
                label: 'Track inventory',
                description: 'Uncheck for services or non-stocked items',
              ),
              AppSwitchRow(
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                label: 'Active',
                description: 'Uncheck to hide from sales without deleting',
              ),
              FilterLabel('Notes', AppInput(controller: _notes, minLines: 2, maxLines: 4)),
            ]),
          ]),
        ),
        actions: [
          OutlinedButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            style: OutlinedButton.styleFrom(backgroundColor: TColors.red600, foregroundColor: Colors.white, side: BorderSide.none),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : (editing ? 'Save changes' : 'Create'))),
        ],
      ),
    );
  }
}
