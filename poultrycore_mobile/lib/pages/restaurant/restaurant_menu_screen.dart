// Restaurant → Menu & Setup → Menu Items, as `app/restaurant-menu/page.tsx`
// ("Menu Management"): the header and its counts, four stat cards, and three
// tabs — Menu Items (search, category filter, 86 / edit / delete), Categories
// and Combos (expand a combo to add or remove its items). Add / Edit Menu Item
// carries the name list with "Other", a category typed inline, a photo
// thumbnail, pricing with margin, details, dietary options and, once saved,
// the recipe.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/sales/balances_widgets.dart' show LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import 'restaurant_roles.dart' show restaurantRose;

/// DIETARY_OPTIONS: key, label, emoji, and the chip's bg / fg / border.
const restaurantDietary = <(String, String, String, Color, Color, Color)>[
  ('isVegetarian', 'Vegetarian', '🥬', Color(0xFFDCFCE7), Color(0xFF15803D), Color(0xFFBBF7D0)),
  ('isVegan', 'Vegan', '🌱', Color(0xFFD1FAE5), Color(0xFF047857), Color(0xFFA7F3D0)),
  ('isGlutenFree', 'Gluten-Free', '🌾', Color(0xFFFEF3C7), Color(0xFFB45309), Color(0xFFFDE68A)),
  ('isHalal', 'Halal', '☪️', Color(0xFFDBEAFE), Color(0xFF1D4ED8), Color(0xFFBFDBFE)),
  ('isKosher', 'Kosher', '✡️', Color(0xFFF3E8FF), Color(0xFF7E22CE), Color(0xFFE9D5FF)),
];

/// The margin on a price, rounded, or null without a cost.
int? menuMargin(num price, num cost) => cost > 0 && price != 0 ? ((price - cost) / price * 100).round() : null;

Color _marginColor(int m) => m >= 60 ? const Color(0xFF16A34A) : m >= 30 ? const Color(0xFFD97706) : const Color(0xFFDC2626);

/// An image the web stored as a data URI, or a plain URL; nothing when it
/// cannot be read (the web hides a broken image).
Widget? menuImage(String src, {double size = 56}) {
  if (src.isEmpty) return null;
  Widget img;
  if (src.startsWith('data:')) {
    final comma = src.indexOf(',');
    try {
      img = Image.memory(base64Decode(src.substring(comma + 1)), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink());
    } catch (_) {
      return null;
    }
  } else {
    img = Image.network(src, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink());
  }
  return ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: size, height: size, child: img));
}

class RestaurantMenuScreen extends StatefulWidget {
  const RestaurantMenuScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantMenuScreen> createState() => _RestaurantMenuScreenState();
}

class _RestaurantMenuScreenState extends State<RestaurantMenuScreen> {
  bool _loading = true;
  String _tab = 'items';
  String _search = '';
  int? _filterCat;
  List<Map> _categories = [], _items = [], _combos = [], _categoryTypes = [], _itemNames = [], _ingredients = [];
  final Map<int, List<Map>> _comboItems = {};
  final Set<int> _expanded = {};

  ApiClient get _api => widget.session.farmClient;
  Map<String, dynamic> get _q => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  List<Map> _rows(Object? r) => [for (final x in (r is List ? r : const [])) if (x is Map) x];

  Future<List<Map>> _list(String path) async => _rows(await _api.get(path, query: _q));

  Future<List<Map>> _quiet(String path) async {
    try {
      return await _list(path);
    } catch (_) {
      return [];
    }
  }

  // listMenuItemNames: the Restaurant route, else the shared seed list.
  Future<List<Map>> _names() async {
    try {
      return await _list('/api/Restaurant/menu/item-names');
    } catch (_) {
      return _quiet('/api/Hotel/setup/menu-item-names');
    }
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([
        _list('/api/Restaurant/menu/categories'),
        _list('/api/Restaurant/menu/items'),
        _list('/api/Restaurant/menu/combos'),
        _quiet('/api/Hotel/setup/menu-category-types'),
        _names(),
        _quiet('/api/Restaurant/inventory/ingredients'),
      ]);
      _categories = r[0];
      _items = r[1];
      _combos = r[2];
      _categoryTypes = r[3];
      _itemNames = r[4];
      _ingredients = r[5];
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to load', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reloadCategories() async {
    _categories = await _list('/api/Restaurant/menu/categories');
    if (mounted) setState(() {});
  }

  Future<void> _reloadItems() async {
    _items = await _list('/api/Restaurant/menu/items');
    if (mounted) setState(() {});
  }

  Future<void> _reloadCombos() async {
    _combos = await _list('/api/Restaurant/menu/combos');
    if (mounted) setState(() {});
  }

  void _fail(Object e) => trackerToast(context, 'Failed', description: e is ApiException ? e.message : '$e', error: true);

  int _catId(Map c) => tIntOrNull(c['menuCategoryId']) ?? 0;
  int _itemCount(int catId) => _items.where((i) => tIntOrNull(i['menuCategoryId']) == catId).length;

  // ------------------------------------------------------------- items
  Future<void> _deleteItem(Map i) async {
    try {
      await _api.delete('/api/Restaurant/menu/items/${i['menuItemId']}', query: _q);
      if (mounted) trackerToast(context, 'Deleted');
      await _reloadItems();
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _toggle86(Map i) async {
    final available = i['isAvailable'] == true;
    try {
      await _api.patch('/api/Restaurant/menu/items/${i['menuItemId']}/availability', query: {..._q, 'isAvailable': '${!available}'});
      if (mounted) trackerToast(context, available ? "Item 86'd" : 'Item back on menu');
      await _reloadItems();
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _openItem([Map? item]) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => RestaurantMenuItemForm(
        session: widget.session,
        company: widget.company,
        existing: item,
        categories: _categories,
        itemNames: _itemNames,
        ingredients: _ingredients,
      ),
    ));
    if (changed == true) {
      await Future.wait([_reloadItems(), _reloadCategories()]);
      _itemNames = await _names();
      if (mounted) setState(() {});
    }
  }

  // -------------------------------------------------------- categories
  Future<void> _deleteCategory(Map c) async {
    try {
      await _api.delete('/api/Restaurant/menu/categories/${_catId(c)}', query: _q);
      if (mounted) trackerToast(context, 'Deleted');
      await _reloadCategories();
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _openCategory([Map? c]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CategoryDialog(
        api: _api,
        farmId: widget.company.farmId,
        existing: c,
        categories: _categories,
        categoryTypes: _categoryTypes,
      ),
    );
    if (saved == true) await _reloadCategories();
  }

  // ------------------------------------------------------------ combos
  Future<void> _deleteCombo(Map cb) async {
    try {
      await _api.delete('/api/Restaurant/menu/combos/${cb['comboId']}', query: _q);
      if (mounted) trackerToast(context, 'Deleted');
      await _reloadCombos();
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _openCombo([Map? cb]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ComboDialog(api: _api, farmId: widget.company.farmId, existing: cb),
    );
    if (saved == true) await _reloadCombos();
  }

  Future<void> _loadComboItems(int id) async {
    _comboItems[id] = await _list('/api/Restaurant/menu/combos/$id/items');
    if (mounted) setState(() {});
  }

  Future<void> _toggleCombo(int id) async {
    if (_expanded.contains(id)) {
      setState(() => _expanded.remove(id));
      return;
    }
    if (!_comboItems.containsKey(id)) {
      try {
        await _loadComboItems(id);
      } catch (e) {
        _fail(e);
        return;
      }
    }
    setState(() => _expanded.add(id));
  }

  Future<void> _removeComboItem(Map ci, int comboId) async {
    try {
      await _api.delete('/api/Restaurant/menu/combos/items/${ci['comboItemId']}', query: _q);
      await _loadComboItems(comboId);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _addComboItem(int comboId) async {
    var pick = _items.isEmpty ? 0 : tIntOrNull(_items.first['menuItemId']) ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Add Item to Combo'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Select a menu item to include in this combo', style: TextStyle(fontSize: 13, color: TColors.slate500)),
              const SizedBox(height: 12),
              const Text('Menu Item', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              AppSelect<int>(
                value: _items.any((i) => tIntOrNull(i['menuItemId']) == pick) ? pick : null,
                items: [
                  for (final i in _items)
                    AppSelectItem(value: tIntOrNull(i['menuItemId']) ?? 0, label: '${tStr(i['name'])} — ${tNum(i['price']).toStringAsFixed(2)}'),
                ],
                onChanged: (v) => set(() => pick = v ?? pick),
              ),
            ]),
          ),
          actions: [
            OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: restaurantRose),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add to Combo'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || pick == 0) return;
    try {
      await _api.post('/api/Restaurant/menu/combos/$comboId/items',
          body: {'menuItemId': pick, 'quantity': 1, 'sortOrder': 0, 'farmId': widget.company.farmId});
      if (mounted) trackerToast(context, 'Item added');
      await _loadComboItems(comboId);
    } catch (e) {
      _fail(e);
    }
  }

  // --------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-menu');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Menu Management')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'))
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
                _header(),
                const SizedBox(height: 14),
                _stats(),
                const SizedBox(height: 14),
                _tabs(),
                const SizedBox(height: 12),
                if (_tab == 'items') _itemsTab(),
                if (_tab == 'categories') _categoriesTab(),
                if (_tab == 'combos') _combosTab(),
              ]),
            ),
    );
  }

  Widget _tile(IconData icon, Color bg, Color fg, {double size = 40, double radius = 8}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
        child: Icon(icon, size: size / 2, color: fg),
      );

  Widget _roseButton(String label, VoidCallback onTap, {bool full = false}) => FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: restaurantRose, minimumSize: full ? const Size.fromHeight(44) : null),
        onPressed: onTap,
        icon: const Icon(Icons.add, size: 18),
        label: Text(label),
      );

  Widget _header() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _tile(Icons.restaurant, const Color(0xFFFFE4E6), restaurantRose),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Menu Management', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
              Text('${_items.length} items across ${_categories.length} categories', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        _roseButton('Add Menu Item', () => _openItem(), full: true),
      ]);

  Widget _stats() {
    final available = _items.where((i) => i['isAvailable'] == true).length;
    final cards = [
      ('Total Items', _items.length, const Color(0xFF111827), Colors.white),
      ('Available', available, const Color(0xFF15803D), const Color(0xFFF0FDF4)),
      ("86'd Items", _items.length - available, const Color(0xFFB91C1C), const Color(0xFFFEF2F2)),
      ('Combos', _combos.length, const Color(0xFF1D4ED8), const Color(0xFFEFF6FF)),
    ];
    // A set tile height: a width ratio left the tiles too short on a 360 px phone.
    return GridView(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 92),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final (label, value, fg, bg) in cards)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: bg, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$value', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: fg)),
              Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
          ),
      ],
    );
  }

  Widget _tabs() {
    final tabs = [
      ('items', Icons.restaurant, 'Menu Items', _items.length),
      ('categories', Icons.grid_view, 'Categories', _categories.length),
      ('combos', Icons.inventory_2_outlined, 'Combos', _combos.length),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Wrap(spacing: 4, runSpacing: 4, children: [
        for (final (v, icon, label, n) in tabs)
          Material(
            color: _tab == v ? const Color(0xFFFFF1F2) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => setState(() => _tab = v),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 16, color: _tab == v ? const Color(0xFFBE123C) : TColors.slate600),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _tab == v ? const Color(0xFFBE123C) : TColors.slate600)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: TColors.slate100, borderRadius: BorderRadius.circular(999)),
                    child: Text('$n', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: TColors.slate700)),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _chip(String text, {Color bg = const Color(0xFFF9FAFB), Color fg = TColors.slate700, Color border = TColors.slate200}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: fg)),
      );

  Widget _empty(IconData icon, String title, String body, {Widget? action}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
        decoration: BoxDecoration(border: Border.all(color: TColors.slate200, width: 2), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Icon(icon, size: 44, color: const Color(0xFFD1D5DB)),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF111827))),
          const SizedBox(height: 4),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          if (action != null) ...[const SizedBox(height: 14), action],
        ]),
      );

  Widget _itemsTab() {
    final rows = [
      for (final i in _items)
        if ((_filterCat == null || tIntOrNull(i['menuCategoryId']) == _filterCat) &&
            (_search.isEmpty || tStr(i['name']).toLowerCase().contains(_search.toLowerCase())))
          i,
    ];
    final filtering = _search.isNotEmpty || _filterCat != null;
    return TCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppInput(hintText: 'Search menu items...', prefixIcon: const Icon(Icons.search, size: 18), onChanged: (v) => setState(() => _search = v)),
        const SizedBox(height: 8),
        AppSelect<int>(
          value: _filterCat ?? 0,
          items: [
            const AppSelectItem(value: 0, label: 'All Categories'),
            for (final c in _categories) AppSelectItem(value: _catId(c), label: '${tStr(c['name'])} (${_itemCount(_catId(c))})'),
          ],
          onChanged: (v) => setState(() => _filterCat = v == 0 ? null : v),
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          _empty(
            Icons.restaurant,
            filtering ? 'No items match your search' : 'No menu items yet',
            filtering ? 'Try adjusting your search or filter' : 'Start building your menu by adding your first item',
            action: filtering ? null : _roseButton('Add your first item', () => _openItem()),
          )
        else
          for (final i in rows) ...[_itemRow(i), const SizedBox(height: 8)],
      ]),
    );
  }

  Widget _itemRow(Map i) {
    final available = i['isAvailable'] == true;
    final price = tNum(i['price']), cost = tNum(i['costPrice']);
    final margin = menuMargin(price, cost);
    final spicy = tNum(i['spicyLevel']).toInt();
    final image = menuImage(tStr(i['imageUrl']));
    final meta = [
      if (tNum(i['prepTime']) > 0) (Icons.schedule, '${tNum(i['prepTime']).toInt()} min'),
      if (i['calories'] != null && tStr(i['calories']).isNotEmpty && tNum(i['calories']) != 0) (null, '${tStr(i['calories'])} cal'),
      if (tStr(i['allergens']).isNotEmpty) (Icons.warning_amber_outlined, tStr(i['allergens'])),
      if (tStr(i['sku']).isNotEmpty) (null, 'SKU: ${tStr(i['sku'])}'),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: available ? null : const Color(0x80FEF2F2),
        border: Border.all(color: available ? TColors.slate200 : const Color(0xFFFECACA)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (image != null) ...[image, const SizedBox(width: 12)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(tStr(i['name']), style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                if (tStr(i['categoryName']).isNotEmpty) _chip(tStr(i['categoryName'])),
                if (!available) _chip("86'd — Unavailable", bg: const Color(0xFFFEE2E2), fg: const Color(0xFFB91C1C), border: const Color(0xFFFEE2E2)),
                for (final (key, label, emoji, bg, fg, border) in restaurantDietary)
                  if (i[key] == true) _chip('$emoji $label', bg: bg, fg: fg, border: border),
                if (spicy > 0) Text('🌶️' * spicy.clamp(0, 5), style: const TextStyle(fontSize: 12)),
              ]),
              if (tStr(i['description']).isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(tStr(i['description']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
              ],
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 12, runSpacing: 2, children: [
                  for (final (icon, text) in meta)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      if (icon != null) ...[Icon(icon, size: 12, color: TColors.slate500), const SizedBox(width: 4)],
                      Text(text, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                    ]),
                ]),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(price.toStringAsFixed(2), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
            if (cost > 0)
              Text.rich(TextSpan(children: [
                TextSpan(text: 'Cost: ${cost.toStringAsFixed(2)}'),
                if (margin != null) TextSpan(text: ' $margin%', style: TextStyle(fontWeight: FontWeight.w500, color: _marginColor(margin))),
              ]), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          ]),
        ]),
        // Always shown: the web's hover-only row buttons are visible on touch.
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          IconButton(
            tooltip: available ? "Mark 86'd" : 'Back on menu',
            icon: Icon(available ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18,
                color: available ? TColors.slate500 : const Color(0xFF16A34A)),
            onPressed: () => _toggle86(i),
          ),
          IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _openItem(i)),
          IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)), onPressed: () => _deleteItem(i)),
        ]),
      ]),
    );
  }

  Widget _cardHead(IconData icon, Color bg, Color fg, String title, String description, String button, VoidCallback onAdd) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _tile(icon, bg, fg, size: 36),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              Text(description, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        _roseButton(button, onAdd, full: true),
        const SizedBox(height: 12),
      ]);

  Widget _categoriesTab() => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _cardHead(Icons.grid_view, const Color(0xFFFEF3C7), const Color(0xFFD97706), 'Menu Categories',
              'Organize your menu items into logical groups', 'Add Category', () => _openCategory()),
          if (_categories.isEmpty)
            _empty(Icons.grid_view, 'No categories yet', 'Create categories like Appetizers, Main Course, Desserts, Beverages',
                action: OutlinedButton.icon(onPressed: () => _openCategory(), icon: const Icon(Icons.add, size: 18), label: const Text('Create your first category')))
          else
            for (final c in _categories) ...[
              Builder(builder: (_) {
                final n = _itemCount(_catId(c));
                final active = c['isActive'] != false;
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    _tile(Icons.grid_view, active ? const Color(0xFFFFE4E6) : const Color(0xFFF3F4F6), active ? restaurantRose : const Color(0xFF9CA3AF),
                        size: 48, radius: 12),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Text(tStr(c['name']), style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                          if (!active) _chip('Inactive', bg: TColors.slate100, border: TColors.slate100),
                        ]),
                        if (tStr(c['description']).isNotEmpty)
                          Text(tStr(c['description']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                        const SizedBox(height: 2),
                        Text('$n item${n != 1 ? 's' : ''}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                      ]),
                    ),
                    IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 16), onPressed: () => _openCategory(c)),
                    IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)), onPressed: () => _deleteCategory(c)),
                  ]),
                );
              }),
              const SizedBox(height: 8),
            ],
        ]),
      );

  Widget _combosTab() => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _cardHead(Icons.inventory_2_outlined, const Color(0xFFDBEAFE), const Color(0xFF2563EB), 'Combos & Meal Deals',
              'Bundle menu items together at a special price', 'Add Combo', () => _openCombo()),
          if (_combos.isEmpty)
            _empty(Icons.inventory_2_outlined, 'No combos yet', 'Create meal deals by bundling items together at a discounted price',
                action: OutlinedButton.icon(onPressed: () => _openCombo(), icon: const Icon(Icons.add, size: 18), label: const Text('Create your first combo')))
          else
            for (final cb in _combos) ...[_comboRow(cb), const SizedBox(height: 10)],
        ]),
      );

  Widget _comboRow(Map cb) {
    final id = tIntOrNull(cb['comboId']) ?? 0;
    final open = _expanded.contains(id);
    final active = cb['isActive'] != false;
    final rows = _comboItems[id] ?? const [];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => _toggleCombo(id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            child: Row(children: [
              _tile(Icons.inventory_2_outlined, active ? const Color(0xFFDBEAFE) : const Color(0xFFF3F4F6),
                  active ? const Color(0xFF2563EB) : const Color(0xFF9CA3AF)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(tStr(cb['name']), style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                    if (!active) _chip('Inactive', bg: TColors.slate100, border: TColors.slate100),
                  ]),
                  if (tStr(cb['description']).isNotEmpty)
                    Text(tStr(cb['description']), style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                ]),
              ),
              Text(tNum(cb['price']).toStringAsFixed(2), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
              Icon(open ? Icons.expand_more : Icons.chevron_right, size: 18, color: const Color(0xFF9CA3AF)),
              IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 16), onPressed: () => _openCombo(cb)),
              IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)), onPressed: () => _deleteCombo(cb)),
            ]),
          ),
        ),
        if (open)
          Container(
            decoration: const BoxDecoration(color: Color(0x80F9FAFB), border: Border(top: BorderSide(color: TColors.slate200))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (k, ci) in rows.indexed) ...[
                if (k > 0) const Divider(height: 1, color: TColors.slate200),
                Padding(
                  padding: const EdgeInsets.only(left: 56, right: 4),
                  child: Row(children: [
                    Text('${tStr(ci['quantity'])}x', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: restaurantRose)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tStr(ci['menuItemName']).isNotEmpty
                            ? tStr(ci['menuItemName'])
                            : tStr(ci['categoryName']).isNotEmpty
                                ? tStr(ci['categoryName'])
                                : 'Unknown',
                        style: const TextStyle(fontSize: 14, color: Color(0xFF374151)),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFEF4444)),
                      onPressed: () => _removeComboItem(ci, id),
                    ),
                  ]),
                ),
              ],
              Padding(
                padding: const EdgeInsets.only(left: 48, bottom: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: restaurantRose),
                    onPressed: () => _addComboItem(id),
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Add item to combo', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ dialogs

Widget _label(String text, {bool required = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: text),
        if (required) const TextSpan(text: ' *', style: TextStyle(color: Color(0xFFF43F5E))),
      ]), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
    );

/// Add / Edit Category: the type picker fills the name, which stays editable.
class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({required this.api, required this.farmId, this.existing, required this.categories, required this.categoryTypes});
  final ApiClient api;
  final String farmId;
  final Map? existing;
  final List<Map> categories;
  final List<Map> categoryTypes;
  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final Map? c = widget.existing;
  late final _name = TextEditingController(text: tStr(c?['name']));
  late final _description = TextEditingController(text: tStr(c?['description']));
  late final _sort = TextEditingController(text: '${tNum(c?['sortOrder']).toInt()}');
  late int? _parent = tIntOrNull(c?['parentCategoryId']);

  @override
  void dispose() {
    for (final x in [_name, _description, _sort]) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return trackerToast(context, 'Category name required', error: true);
    final editingId = tIntOrNull(c?['menuCategoryId']);
    final dup = widget.categories.any((x) => tStr(x['name']).toLowerCase() == name.toLowerCase() && tIntOrNull(x['menuCategoryId']) != editingId);
    if (dup) return trackerToast(context, 'Duplicate name', description: 'A category named "${_name.text}" already exists.', error: true);
    final body = {
      'name': _name.text,
      if (c != null || _description.text.isNotEmpty) 'description': _description.text,
      'parentCategoryId': _parent,
      if (c != null) 'imageUrl': c!['imageUrl'],
      'sortOrder': int.tryParse(_sort.text) ?? 0,
      'isActive': c == null ? true : c!['isActive'],
      'farmId': widget.farmId,
    };
    try {
      if (c != null) {
        await widget.api.put('/api/Restaurant/menu/categories/$editingId', body: body);
      } else {
        await widget.api.post('/api/Restaurant/menu/categories', body: body);
      }
      if (!mounted) return;
      trackerToast(context, c != null ? 'Category updated' : 'Category created');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(c != null ? 'Edit Category' : 'Add Category'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Organize your menu items into logical groups', style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 14),
            _label('Category Type', required: true),
            AppSelect<String>(
              value: null,
              hintText: 'Select a category type',
              items: [
                const AppSelectItem(value: '__none__', label: 'Select type'),
                for (final t in widget.categoryTypes) AppSelectItem(value: tStr(t['description']), label: tStr(t['description'])),
              ],
              onChanged: (v) {
                if (v == null || v == '__none__') return;
                setState(() => _name.text = v);
              },
            ),
            const SizedBox(height: 12),
            _label('Category Name', required: true),
            AppInput(controller: _name, hintText: 'Auto-filled from type, but editable'),
            const SizedBox(height: 4),
            const Text('Auto-filled from the type above. Edit to customise (e.g. "House Appetizers").',
                style: TextStyle(fontSize: 12, color: TColors.slate500)),
            const SizedBox(height: 12),
            _label('Description'),
            AppInput(controller: _description, hintText: 'Brief description (optional)'),
            const SizedBox(height: 12),
            _label('Parent Category'),
            AppSelect<int>(
              value: _parent ?? 0,
              items: [
                const AppSelectItem(value: 0, label: 'None (top-level)'),
                for (final x in widget.categories)
                  if (tIntOrNull(x['menuCategoryId']) != tIntOrNull(c?['menuCategoryId']))
                    AppSelectItem(value: tIntOrNull(x['menuCategoryId']) ?? 0, label: tStr(x['name'])),
              ],
              onChanged: (v) => setState(() => _parent = v == 0 ? null : v),
            ),
            const SizedBox(height: 12),
            _label('Sort Order'),
            AppInput(controller: _sort, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))]),
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: restaurantRose), onPressed: _save, child: Text(c != null ? 'Update' : 'Create Category')),
        ],
      );
}

/// Add Combo / Meal Deal.
class _ComboDialog extends StatefulWidget {
  const _ComboDialog({required this.api, required this.farmId, this.existing});
  final ApiClient api;
  final String farmId;
  final Map? existing;
  @override
  State<_ComboDialog> createState() => _ComboDialogState();
}

class _ComboDialogState extends State<_ComboDialog> {
  late final Map? cb = widget.existing;
  late final _name = TextEditingController(text: tStr(cb?['name']));
  late final _price = TextEditingController(text: _num(tNum(cb?['price'])));
  late final _description = TextEditingController(text: tStr(cb?['description']));

  @override
  void dispose() {
    for (final x in [_name, _price, _description]) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return trackerToast(context, 'Combo name required', error: true);
    final body = {
      'name': _name.text,
      if (cb != null || _description.text.isNotEmpty) 'description': _description.text,
      'price': double.tryParse(_price.text) ?? 0,
      if (cb != null) 'imageUrl': cb!['imageUrl'],
      'isActive': cb == null ? true : cb!['isActive'],
      'farmId': widget.farmId,
    };
    try {
      if (cb != null) {
        await widget.api.put('/api/Restaurant/menu/combos/${cb!['comboId']}', body: body);
      } else {
        await widget.api.post('/api/Restaurant/menu/combos', body: body);
      }
      if (!mounted) return;
      trackerToast(context, cb != null ? 'Combo updated' : 'Combo created');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(cb != null ? 'Edit Combo' : 'Add Combo / Meal Deal'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Bundle items together at a special price', style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 14),
            _label('Combo Name', required: true),
            AppInput(controller: _name, hintText: 'e.g. Family Meal Deal'),
            const SizedBox(height: 12),
            _label('Combo Price'),
            _MoneyInput(controller: _price),
            const SizedBox(height: 12),
            _label('Description'),
            AppInput(controller: _description, hintText: "What's included in this deal?"),
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: restaurantRose), onPressed: _save, child: Text(cb != null ? 'Update' : 'Create Combo')),
        ],
      );
}

String _num(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

class _MoneyInput extends StatelessWidget {
  const _MoneyInput({required this.controller, this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => AppInput(
        controller: controller,
        prefixIcon: const Icon(Icons.attach_money, size: 16),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
        onChanged: onChanged,
      );
}

/// Add / Edit Menu Item.
class RestaurantMenuItemForm extends StatefulWidget {
  const RestaurantMenuItemForm({
    super.key,
    required this.session,
    required this.company,
    this.existing,
    required this.categories,
    required this.itemNames,
    required this.ingredients,
  });
  final Session session;
  final Company company;
  final Map? existing;
  final List<Map> categories;
  final List<Map> itemNames;
  final List<Map> ingredients;

  @override
  State<RestaurantMenuItemForm> createState() => _RestaurantMenuItemFormState();
}

class _RestaurantMenuItemFormState extends State<RestaurantMenuItemForm> {
  late final Map? e = widget.existing;
  bool get _editing => e != null;
  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  String _nameSelection = '';
  late final _name = TextEditingController(text: tStr(e?['name']));
  // Category: an existing one, or a new name typed inline.
  String _categoryMode = 'pick';
  late int? _categoryId = tIntOrNull(e?['menuCategoryId']);
  final _newCategory = TextEditingController();
  late final _description = TextEditingController(text: tStr(e?['description']));
  late String _imageUrl = tStr(e?['imageUrl']);
  late final _price = TextEditingController(text: _num(tNum(e?['price'])));
  late final _cost = TextEditingController(text: _num(tNum(e?['costPrice'])));
  late final _prep = TextEditingController(text: '${tNum(e?['prepTime']).toInt()}');
  late final _calories = TextEditingController(text: e?['calories'] == null ? '' : tStr(e!['calories']));
  late int _spicy = tNum(e?['spicyLevel']).toInt();
  late final _sku = TextEditingController(text: tStr(e?['sku']));
  late final _allergens = TextEditingController(text: tStr(e?['allergens']));
  late final Map<String, bool> _dietary = {for (final d in restaurantDietary) d.$1: e?[d.$1] == true};

  List<Map> _recipe = [];
  int _addIngredient = 0;
  final _addQty = TextEditingController(text: '1');
  final _addUnit = TextEditingController(text: 'kg');
  final _addWaste = TextEditingController(text: '0');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (_editing) _loadRecipe();
  }

  @override
  void dispose() {
    for (final x in [_name, _newCategory, _description, _price, _cost, _prep, _calories, _sku, _allergens, _addQty, _addUnit, _addWaste]) {
      x.dispose();
    }
    super.dispose();
  }

  int get _itemId => tIntOrNull(e?['menuItemId']) ?? 0;

  Future<void> _loadRecipe() async {
    try {
      final r = await _api.get('/api/Restaurant/inventory/recipes/$_itemId', query: {'farmId': _farmId});
      _recipe = [for (final x in (r is List ? r : const [])) if (x is Map) x];
    } catch (_) {
      _recipe = [];
    }
    if (mounted) setState(() {});
  }

  num _lineCost(Map r) => tNum(r['lineCost']) != 0 ? tNum(r['lineCost']) : tNum(r['quantity']) * tNum(r['costPerUnit']);

  Future<void> _pickPhoto() async {
    try {
      // Downscaled before storing, as fileToThumbnailDataUrl: the data URI goes
      // into the row itself, and every menu list reads it back.
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 72);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() => _imageUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}');
    } catch (err) {
      if (mounted) trackerToast(context, "Couldn't use that image", description: '$err', error: true);
    }
  }

  Map<String, dynamic> _body(int? categoryId) {
    final price = double.tryParse(_price.text) ?? 0;
    final cost = double.tryParse(_cost.text) ?? 0;
    return {
      'name': _name.text,
      'menuCategoryId': categoryId,
      'description': _description.text,
      'price': price,
      'costPrice': cost,
      'imageUrl': _imageUrl,
      'prepTime': int.tryParse(_prep.text) ?? 0,
      'calories': _calories.text.trim().isEmpty ? null : int.tryParse(_calories.text.trim()),
      'allergens': _allergens.text,
      'spicyLevel': _spicy,
      for (final d in restaurantDietary) d.$1: _dietary[d.$1] ?? false,
      'isAvailable': _editing ? e!['isAvailable'] : true,
      'isActive': _editing ? e!['isActive'] : true,
      if (_editing) 'sortOrder': e!['sortOrder'],
      'sku': _sku.text,
      if (_editing) 'barcode': e!['barcode'],
      'farmId': _farmId,
    };
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return trackerToast(context, 'Item name required', error: true);
    if (_categoryMode == 'new' && _newCategory.text.trim().isEmpty) {
      return trackerToast(context, 'Category name required', description: 'Type a name or pick an existing category.', error: true);
    }
    setState(() => _saving = true);
    try {
      // A typed category becomes a real menu category first, so the item is
      // filed under it and it shows in the dropdown from now on.
      var categoryId = _categoryId;
      if (_categoryMode == 'new') {
        final created = await _api.post('/api/Restaurant/menu/categories',
            body: {'name': _newCategory.text.trim(), 'isActive': true, 'farmId': _farmId});
        categoryId = created is Map ? tIntOrNull(created['menuCategoryId']) : null;
      }
      final body = _body(categoryId);
      if (_editing) {
        await _api.put('/api/Restaurant/menu/items/$_itemId', body: body);
      } else {
        await _api.post('/api/Restaurant/menu/items', body: body);
      }
      if (!mounted) return;
      trackerToast(context, _editing ? 'Item updated' : 'Item created');
      // Remember a name typed under "Other" so it is pickable next time. Not
      // fatal: the item is already saved.
      if (_nameSelection == 'Other' && _name.text.trim().isNotEmpty) {
        final picked = categoryId == null
            ? null
            : [for (final c in widget.categories) if (tIntOrNull(c['menuCategoryId']) == categoryId) tStr(c['name'])].firstOrNull;
        final categoryName = picked ?? (_newCategory.text.trim().isEmpty ? null : _newCategory.text.trim());
        try {
          await _api.post('/api/Restaurant/menu/item-names',
              body: {'farmId': _farmId, 'description': _name.text.trim(), 'category': categoryName});
        } on ApiException catch (err) {
          if (mounted) trackerToast(context, 'Item saved, but the name was not remembered', description: err.message);
        }
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (err) {
      if (mounted) {
        setState(() => _saving = false);
        trackerToast(context, 'Failed', description: err.message, error: true);
      }
    }
  }

  Future<void> _addToRecipe() async {
    await _api.post('/api/Restaurant/inventory/recipes', query: {'farmId': _farmId}, body: {
      'menuItemId': _itemId,
      'ingredientId': _addIngredient,
      'quantity': double.tryParse(_addQty.text) ?? 0,
      'unit': _addUnit.text,
      'wastePercent': double.tryParse(_addWaste.text) ?? 0,
      'notes': null,
    });
    await _loadRecipe();
    setState(() {
      _addIngredient = 0;
      _addQty.text = '1';
      _addWaste.text = '0';
    });
    if (mounted) trackerToast(context, 'Ingredient added to recipe');
  }

  Widget _section(IconData? icon, String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 14, color: TColors.slate500), const SizedBox(width: 6)],
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate500)),
          ]),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  Widget _numField(TextEditingController c, {String? hint, bool decimal = false}) => AppInput(
        controller: c,
        hintText: hint,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'^\d*\.?\d*' : r'^\d*'))],
        onChanged: (_) => setState(() {}),
      );

  @override
  Widget build(BuildContext context) {
    final price = double.tryParse(_price.text) ?? 0, cost = double.tryParse(_cost.text) ?? 0;
    final names = [for (final n in widget.itemNames) if (tStr(n['description']).trim().toLowerCase() != 'other') n];
    final image = menuImage(_imageUrl, size: 64);
    final unused = [for (final i in widget.ingredients) if (!_recipe.any((r) => tIntOrNull(r['ingredientId']) == tIntOrNull(i['ingredientId']))) i];
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit Menu Item' : 'Add Menu Item')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
        const Text('Fill in the details for this menu item', style: TextStyle(fontSize: 13, color: TColors.slate500)),
        const SizedBox(height: 16),
        _section(null, 'Basic Information', [
          _label('Item Name', required: true),
          AppSelect<String>(
            value: _nameSelection.isEmpty ? null : _nameSelection,
            hintText: 'Select or type a name',
            items: [
              const AppSelectItem(value: '__none__', label: 'Select item'),
              for (final n in names)
                AppSelectItem(
                  value: tStr(n['description']),
                  label: '${tStr(n['description'])}${tStr(n['category']).isNotEmpty && tStr(n['category']) != tStr(n['description']) ? ' (${tStr(n['category'])})' : ''}',
                ),
              const AppSelectItem(value: 'Other', label: 'Other'),
            ],
            onChanged: (v) => setState(() {
              _nameSelection = v == null || v == '__none__' ? '' : v;
              if (_nameSelection.isNotEmpty && _nameSelection != 'Other') _name.text = _nameSelection;
              if (_nameSelection == 'Other') _name.clear();
            }),
          ),
          if (_nameSelection == 'Other' || _editing) ...[
            const SizedBox(height: 6),
            AppInput(controller: _name, hintText: 'Type item name'),
          ],
          const SizedBox(height: 12),
          _label('Category'),
          AppSelect<int>(
            value: _categoryMode == 'new' ? -1 : (_categoryId ?? 0),
            items: [
              const AppSelectItem(value: 0, label: 'Uncategorized'),
              for (final c in widget.categories) AppSelectItem(value: tIntOrNull(c['menuCategoryId']) ?? 0, label: tStr(c['name'])),
              const AppSelectItem(value: -1, label: '+ New category…'),
            ],
            onChanged: (v) => setState(() {
              if (v == -1) {
                _categoryMode = 'new';
                _categoryId = null;
              } else {
                _categoryMode = 'pick';
                _newCategory.clear();
                _categoryId = v == 0 ? null : v;
              }
            }),
          ),
          if (_categoryMode == 'new') ...[
            const SizedBox(height: 6),
            AppInput(controller: _newCategory, hintText: 'Type a new category'),
          ],
          const SizedBox(height: 12),
          _label('Description'),
          AppTextarea(controller: _description, hintText: 'Describe this dish...', rows: 2),
          const SizedBox(height: 12),
          _label('Image (optional)'),
          Row(children: [
            OutlinedButton.icon(
              onPressed: _pickPhoto,
              icon: const Icon(Icons.inventory_2_outlined, size: 16, color: restaurantRose),
              label: const Text('Choose Photo'),
            ),
            if (image != null) ...[
              const SizedBox(width: 12),
              Stack(children: [
                image,
                Positioned(
                  top: 0,
                  right: 0,
                  child: InkWell(
                    onTap: () => setState(() => _imageUrl = ''),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: Color(0xFFEF4444), borderRadius: BorderRadius.only(bottomLeft: Radius.circular(8))),
                      child: const Icon(Icons.delete_outline, size: 12, color: Colors.white),
                    ),
                  ),
                ),
              ]),
            ],
          ]),
        ]),
        _section(Icons.attach_money, 'Pricing', [
          _label('Selling Price', required: true),
          _MoneyInput(controller: _price, onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          _label('Cost Price'),
          _MoneyInput(controller: _cost, onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          _label('Margin'),
          Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFFF9FAFB), border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
            child: Text(cost != 0 && price != 0 ? '${((price - cost) / price * 100).round()}%' : '—',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ]),
        _section(Icons.schedule, 'Details', [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_label('Prep Time (min)'), _numField(_prep)])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_label('Calories'), _numField(_calories, hint: '—')])),
          ]),
          const SizedBox(height: 12),
          _label('Spicy Level'),
          Wrap(spacing: 4, children: [
            for (var l = 0; l <= 5; l++)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _spicy = l),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _spicy == l ? const Color(0xFFEF4444) : const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8)),
                  child: Text(l == 0 ? '0' : '🌶️', style: TextStyle(fontSize: 14, color: _spicy == l ? Colors.white : const Color(0xFF6B7280))),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          _label('SKU'),
          AppInput(controller: _sku, hintText: 'Optional'),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.warning_amber_outlined, size: 14, color: Color(0xFFF59E0B)),
            const SizedBox(width: 6),
            Expanded(child: _label('Allergens')),
          ]),
          AppInput(controller: _allergens, hintText: 'e.g. Nuts, Dairy, Gluten, Shellfish'),
        ]),
        _section(Icons.eco_outlined, 'Dietary Options', [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (key, label, emoji, bg, fg, _) in restaurantDietary)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _dietary[key] = !(_dietary[key] ?? false)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _dietary[key] == true ? bg : null,
                    border: Border.all(color: _dietary[key] == true ? fg : const Color(0xFFE5E7EB), width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$emoji $label',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _dietary[key] == true ? fg : const Color(0xFF6B7280))),
                ),
              ),
          ]),
        ]),
        if (_editing)
          _section(Icons.inventory_2_outlined, 'Recipe / Ingredients', [
            Align(
              alignment: Alignment.centerRight,
              child: Text('Cost: ${_recipe.fold<num>(0, (s, r) => s + _lineCost(r)).toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ),
            for (final r in _recipe)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate200))),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tStr(r['ingredientName']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      Text('${tStr(r['quantity'])} ${tStr(r['unit'])} · waste ${tStr(r['wastePercent'])}%',
                          style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                    ]),
                  ),
                  Text(_lineCost(r).toStringAsFixed(2), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFEF4444)),
                    onPressed: () async {
                      await _api.delete('/api/Restaurant/inventory/recipes/${r['recipeId']}', query: {'farmId': _farmId});
                      await _loadRecipe();
                    },
                  ),
                ]),
              ),
            const SizedBox(height: 10),
            _label('Ingredient'),
            AppSelect<int>(
              value: _addIngredient,
              items: [
                const AppSelectItem(value: 0, label: 'Select ingredient'),
                for (final i in unused) AppSelectItem(value: tIntOrNull(i['ingredientId']) ?? 0, label: '${tStr(i['name'])} (${tStr(i['unit'])})'),
              ],
              onChanged: (v) => setState(() {
                _addIngredient = v ?? 0;
                final ing = widget.ingredients.where((i) => tIntOrNull(i['ingredientId']) == v).firstOrNull;
                if (ing != null) _addUnit.text = tStr(ing['unit']);
              }),
            ),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_label('Qty'), _numField(_addQty, decimal: true)])),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_label('Unit'), AppInput(controller: _addUnit)])),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_label('Waste %'), _numField(_addWaste, decimal: true)])),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Add ingredient',
                style: IconButton.styleFrom(backgroundColor: restaurantRose),
                onPressed: _addIngredient == 0 ? null : _addToRecipe,
                icon: const Icon(Icons.add, size: 18),
              ),
            ]),
            if (_recipe.isEmpty) ...[
              const SizedBox(height: 8),
              const Text('No ingredients defined. Add ingredients to auto-deduct stock when orders are completed.',
                  style: TextStyle(fontSize: 12, color: TColors.slate500)),
            ],
          ])
        else
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 22),
            decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(8)),
            child: const Row(children: [
              Icon(Icons.inventory_2_outlined, size: 16, color: TColors.slate500),
              SizedBox(width: 6),
              Expanded(
                child: Text('Save the item first, then edit it to define the recipe/ingredients.',
                    style: TextStyle(fontSize: 12, color: TColors.slate500)),
              ),
            ]),
          ),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: restaurantRose, minimumSize: const Size.fromHeight(46)),
              onPressed: _saving ? null : _save,
              child: Text(_editing ? 'Update Item' : 'Add Item'),
            ),
          ),
        ]),
      ]),
    );
  }
}
