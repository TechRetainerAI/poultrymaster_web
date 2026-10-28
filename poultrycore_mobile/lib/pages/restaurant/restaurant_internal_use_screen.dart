// Restaurant → Expenses → Internal Use, as `app/restaurant-internal-use/page.tsx`
// (migration 330): Poultry's page in rose. Stock the restaurant uses itself —
// staff meals, owner use, complimentary food, donations, tasting — recorded at
// cost, never as a sale. Draft → Posted → Reversed, "Post again", and a
// reversed record edits and deletes like a draft. A line is a stock item OR a
// menu item; a menu item takes its recipe out of stock.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/expenses/deferred_costs_screen.dart' show qtyFmt;
import '../poultry/expenses/internal_use_screen.dart' show internalUseReversalReasons, internalUseTone;
import '../poultry/money/money_widgets.dart';
import '../poultry/money/reconciliation_screen.dart' show ReasonPromptDialog;
import '../poultry/reports/report_format.dart';
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';
import 'restaurant_roles.dart' show restaurantRose;
import 'restaurant_widgets.dart' show RPageHeader, roseButton;

const restaurantInternalUseCategories = ['StaffWelfare', 'OwnerUse', 'Sample', 'Donation', 'QualityTest', 'InternalConsumption', 'Other'];
const _labels = {
  'StaffWelfare': 'Staff meal',
  'OwnerUse': 'Owner use',
  'Sample': 'Complimentary / sample',
  'Donation': 'Donation',
  'QualityTest': 'Quality testing',
  'InternalConsumption': 'Kitchen use',
  'Other': 'Other',
};
String restaurantInternalUseLabel(Object? c) => _labels[tStr(c)] ?? tStr(c);

/// What differs on Hotel's copy of this page (`app/hotel-internal-use`,
/// migration 334): its route, its own reasons, "Supply" for a stock line, the
/// wording, and violet. Its API speaks `itemId` for the stock item.
class InternalUseFlavor {
  const InternalUseFlavor({
    required this.api,
    required this.href,
    required this.inventoryHref,
    required this.categories,
    required this.labels,
    required this.stockType,
    required this.subtitle,
    required this.recipientHint,
    required this.accent,
    required this.soft,
    required this.border,
    required this.ink,
    required this.tile,
    this.itemIdKey = false,
  });
  final String api, href, inventoryHref, stockType, subtitle, recipientHint;
  final List<String> categories;
  final Map<String, String> labels;
  final Color accent, soft, border, ink, tile;

  /// Hotel: each line also carries `itemId` (toApi), and comes back with it.
  final bool itemIdKey;

  String label(Object? c) => labels[tStr(c)] ?? tStr(c);
}

const restaurantInternalUseFlavor = InternalUseFlavor(
  api: '/api/Restaurant/internal-usage',
  href: '/restaurant-internal-use',
  inventoryHref: '/restaurant-inventory',
  categories: restaurantInternalUseCategories,
  labels: _labels,
  stockType: 'Ingredient',
  subtitle: 'Food, drinks or supplies used by the restaurant — given to staff, taken by the owner, donated, sampled or tested. Recorded at cost, never as a sale.',
  recipientHint: 'e.g. Kitchen team',
  accent: restaurantRose,
  soft: TColors.rose50,
  border: TColors.rose200,
  ink: Color(0xFF881337),
  tile: Color(0xFFFFE4E6),
);

/// HOTEL_INTERNAL_USE_CATEGORIES and their labels (lib/api/hotel-supplies.ts).
const hotelInternalUseFlavor = InternalUseFlavor(
  api: '/api/Hotel/internal-usage',
  href: '/hotel-internal-use',
  inventoryHref: '/hotel-inventory',
  categories: ['RoomAmenities', 'Housekeeping', 'StaffWelfare', 'Complimentary', 'Donation', 'Damaged', 'Other'],
  labels: {
    'RoomAmenities': 'Rooms restocked (amenities)',
    'Housekeeping': 'Housekeeping consumption',
    'StaffWelfare': 'Staff use',
    'Complimentary': 'Complimentary / guest gift',
    'Donation': 'Donation',
    'Damaged': 'Damaged / written off',
    'Other': 'Other',
  },
  stockType: 'Supply',
  subtitle: 'Supplies used by the hotel itself — rooms restocked, housekeeping, staff use, complimentary, donated or written off. Recorded at cost, never as a sale.',
  recipientHint: 'e.g. Housekeeping team',
  accent: TColors.violet600,
  soft: TColors.violet50,
  border: Color(0xFFDDD6FE),
  ink: Color(0xFF4C1D95),
  tile: TColors.violet100,
  itemIdKey: true,
);

/// RESTAURANT_STAFF_BASED_CATEGORIES: only a staff meal is entered staff × each.
bool _isStaff(Object? c) => tStr(c) == 'StaffWelfare';

num _r2(num n) => (n * 100).round() / 100;
num _r3(num n) => (n * 1000).round() / 1000;
num _r4(num n) => (n * 10000).round() / 10000;

String _singular(String unit) {
  final u = (unit.isEmpty ? 'unit' : unit).trim();
  return u.toLowerCase().endsWith('s') ? u.substring(0, u.length - 1) : u;
}

String _plural(String unit) {
  final u = unit.trim();
  if (u.isEmpty) return 'Units';
  return u.toLowerCase().endsWith('s') ? u : '${u}s';
}

/// describeQty: "3 portions" / "2.5 kgs" — what was typed, in the item's unit.
String describeRestaurantInternalQty(Map r) {
  final items = rowsOf(r['items']);
  if (items.isEmpty) return '—';
  final line = items.first;
  return '${qtyFmt(line['entryQuantity'])} ${_plural(tStr(line['entryUnit']).isEmpty ? 'unit' : tStr(line['entryUnit'])).toLowerCase()}';
}

/// "Ingredient:12" / "MenuItem:4": one value for either kind of line.
String _optKey(Object? type, Object? id) => '${tStr(type)}:${tIntOrNull(id) ?? 0}';

Widget _badge(Object? s) {
  final (bg, fg) = internalUseTone(s);
  return TBadge(tStr(s), bg: bg, fg: fg);
}

/// The page's filters: date and search (five keys), status, reason.
List<Map> filterRestaurantInternalUse(List<Map> rows,
    {String search = '', String from = '', String to = '', String status = 'ALL', String category = 'ALL'}) {
  final q = search.trim().toLowerCase();
  return rows.where((r) {
    final day = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(tStr(r['usageDate']))?[1];
    if (day != null) {
      if (from.isNotEmpty && day.compareTo(from) < 0) return false;
      if (to.isNotEmpty && day.compareTo(to) > 0) return false;
    }
    if (q.isNotEmpty && !['referenceNo', 'category', 'reason', 'recipientName', 'notes'].any((k) => tStr(r[k]).toLowerCase().contains(q))) {
      return false;
    }
    if (status != 'ALL' && tStr(r['status']) != status) return false;
    if (category != 'ALL' && tStr(r['category']) != category) return false;
    return true;
  }).toList();
}

class RestaurantInternalUseScreen extends StatefulWidget {
  const RestaurantInternalUseScreen({super.key, required this.session, required this.company, this.flavor = restaurantInternalUseFlavor});
  final Session session;
  final Company company;
  final InternalUseFlavor flavor;

  @override
  State<RestaurantInternalUseScreen> createState() => _RestaurantInternalUseScreenState();
}

class _RestaurantInternalUseScreenState extends State<RestaurantInternalUseScreen> {
  List<Map> _items = [], _products = [];
  bool _loading = true;
  final _search = TextEditingController();
  String _from = '', _to = '', _status = 'ALL', _category = 'ALL';
  int _page = 1, _pageSize = 10, _lastTotal = -1;
  FarmMoney _gh = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  InternalUseFlavor get _f => widget.flavor;
  String _u([String path = '']) => '${_f.api}$path?farmId=${Uri.encodeQueryComponent(_farmId)}';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Records and items load separately; either failing toasts on its own.
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = rowsOf(await _api.get(_u()));
      if (mounted) setState(() => _items = r);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, "Couldn't load internal use records", description: e.message, error: true);
    }
    try {
      final p = rowsOf(await _api.get(_u('/items')));
      if (mounted) setState(() => _products = p);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, "Couldn't load products", description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  int _id(Map r) => tIntOrNull(r['internalUsageId']) ?? 0;

  Future<void> _openForm([Map? editing]) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _FormDialog(session: widget.session, company: widget.company, products: _products, fmt: _gh, editing: editing, flavor: _f),
    );
    if (done == true) _load();
  }

  Future<void> _confirm({required String title, required String description, required String action, bool destructive = false, required Future<void> Function() run}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: destructive ? TColors.red600 : _f.accent),
            child: Text(action),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await run();
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, "That didn't work", description: e.message, error: true);
    }
  }

  Future<void> _post(Map r, {bool again = false}) => _confirm(
        title: again ? 'Post this reversed record again?' : 'Post this internal use?',
        description: again
            ? '${describeRestaurantInternalQty(r)} comes back out of stock and ${_gh(tNum(r['totalCostValue']))} is booked as a non-cash expense again. The reversal stays in the stock history.'
            : '${describeRestaurantInternalQty(r)} comes out of stock and ${_gh(tNum(r['totalCostValue']))} is booked as a non-cash expense. No sale and no cash movement is created.',
        action: again ? 'Post again' : 'Post',
        run: () async {
          await _api.post(_u('/${_id(r)}/post'));
          if (mounted) trackerToast(context, 'Posted', description: 'Stock reduced and the cost booked as a non-cash expense.');
        },
      );

  Future<void> _delete(Map r, {bool reversed = false}) => _confirm(
        title: reversed ? 'Delete this reversed record?' : 'Delete this draft?',
        description: reversed
            ? 'The stock came back when this was reversed, so nothing moves now. The out-and-back entries stay in stock history.'
            : 'It has not touched stock, so it can be removed outright.',
        action: 'Delete',
        destructive: true,
        run: () async {
          await _api.delete(_u('/${_id(r)}'));
          if (mounted) trackerToast(context, 'Deleted');
        },
      );

  Future<void> _reverse(Map r) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const ReasonPromptDialog(
        title: 'Reverse this internal use?',
        description: 'The stock comes back with an opposite ledger entry — the original is kept — and the linked expense is cancelled.',
        placeholder: 'Select a reason',
        options: internalUseReversalReasons,
      ),
    );
    if (reason == null) return;
    try {
      await _api.post(_u('/${_id(r)}/reverse'), body: {'farmId': _farmId, 'reason': reason});
      if (mounted) trackerToast(context, 'Reversed', description: 'Stock restored and the expense cancelled.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, "Couldn't reverse", description: e.message, error: true);
    }
  }

  Future<void> _view(Map r) => showDialog<void>(context: context, builder: (_) => _Detail(record: r, fmt: _gh, offset: _offset, flavor: _f));

  /// rowActions: what each status allows.
  List<Widget> _actions(Map r) {
    Widget b(String tip, IconData icon, VoidCallback on, {Color? color}) =>
        IconButton(tooltip: tip, onPressed: on, icon: Icon(icon, size: 18, color: color));
    final view = b('View details', Icons.visibility_outlined, () => _view(r), color: TColors.slate600);
    return switch (tStr(r['status'])) {
      'Draft' => [
          view,
          b('Edit', Icons.edit_outlined, () => _openForm(r)),
          b('Post', Icons.check_circle_outline, () => _post(r), color: const Color(0xFF16A34A)),
          b('Delete', Icons.delete_outline, () => _delete(r), color: TColors.red600),
        ],
      'Posted' => [view, b('Reverse', Icons.undo, () => _reverse(r), color: TColors.amber600)],
      _ => [
          view,
          b('Edit', Icons.edit_outlined, () => _openForm(r)),
          b('Post again', Icons.check_circle_outline, () => _post(r, again: true), color: const Color(0xFF16A34A)),
          b('Delete', Icons.delete_outline, () => _delete(r, reversed: true), color: TColors.red600),
        ],
    };
  }

  String _product(Map r) {
    final items = rowsOf(r['items']);
    return items.isEmpty || tStr(items.first['itemName']).isEmpty ? '—' : tStr(items.first['itemName']);
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: _f.href);
    final visible = filterRestaurantInternalUse(_items, search: _search.text, from: _from, to: _to, status: _status, category: _category);
    if (visible.length != _lastTotal) {
      _lastTotal = visible.length;
      _page = 1;
    }
    final pageRows = pageSlice(visible, _page, _pageSize);
    final postedCost = visible.where((r) => tStr(r['status']) == 'Posted').fold<num>(0, (s, r) => s + tNum(r['totalCostValue']));
    Widget stat(String label, String value) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: TColors.slate900)),
          ]),
        );

    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Internal Use')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            RPageHeader(
              icon: Icons.remove_shopping_cart_outlined,
              title: 'Internal Use',
              subtitle: _f.subtitle,
              tileColor: _f.tile,
              iconColor: _f.accent,
              actions: [roseButton('Record internal use', () => _openForm(), color: _f.accent)],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: _f.soft, border: Border.all(color: _f.border), borderRadius: BorderRadius.circular(6)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, size: 16, color: _f.ink),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Posting writes a stock movement, updates inventory and books a non-cash expense.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _f.ink)),
                ),
              ]),
            ),
            if (!_loading && _products.isEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: const Color(0xFFFDE68A)), borderRadius: BorderRadius.circular(8)),
                child: Wrap(children: [
                  const Text('No products in this company yet. ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.amber900)),
                  const Text('Internal Use takes stock off a product, so add one before recording anything. ',
                      style: TextStyle(fontSize: 13, color: TColors.amber800)),
                  InkWell(
                    onTap: () => openAppHref(context, widget.session, widget.company, _f.inventoryHref, label: 'Inventory'),
                    child: const Text('Go to Inventory',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.amber900, decoration: TextDecoration.underline)),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 14),
            twoUp([
              stat('Records', '${visible.length}'),
              stat('Drafts', '${visible.where((r) => tStr(r['status']) == 'Draft').length}'),
              stat('Posted cost', _gh(postedCost)),
              stat('Reversed', '${visible.where((r) => tStr(r['status']) == 'Reversed').length}'),
            ]),
            const SizedBox(height: 14),
            ListFiltersCard(
              search: _search,
              searchPlaceholder: 'Search reason, recipient or notes',
              onSearch: () => setState(() {}),
              from: _from,
              to: _to,
              onDates: (f, t) => setState(() {
                _from = f;
                _to = t;
              }),
              onClear: () => setState(() {
                _search.clear();
                _from = '';
                _to = '';
              }),
              extras: [
                AppSelect<String>(
                  value: _status,
                  items: const [
                    AppSelectItem(value: 'ALL', label: 'All statuses'),
                    AppSelectItem(value: 'Draft', label: 'Draft'),
                    AppSelectItem(value: 'Posted', label: 'Posted'),
                    AppSelectItem(value: 'Reversed', label: 'Reversed'),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? 'ALL'),
                ),
                AppSelect<String>(
                  value: _category,
                  items: [
                    const AppSelectItem(value: 'ALL', label: 'All reasons'),
                    for (final c in _f.categories) AppSelectItem(value: c, label: _f.label(c)),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? 'ALL'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading…'))
            else if (visible.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                child: const Text('No internal use recorded yet.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
              )
            else
              MobileCardList<Map>(
                striped: true,
                items: pageRows,
                keyOf: (r) => '${_id(r)}',
                primary: (r) => _f.label(r['category']),
                secondary: (r) => fmtDateTime(r['usageDate'], r, _offset),
                trailing: (r) => Padding(padding: const EdgeInsets.only(left: 6), child: _badge(r['status'])),
                highlights: (r) => [
                  Highlight('Quantity', describeRestaurantInternalQty(r), accent: Accent.rose),
                  Highlight('Cost', _gh(tNum(r['totalCostValue'])), accent: Accent.violet),
                ],
                details: (r) => [
                  ('Date', fmtDateTime(r['usageDate'], r, _offset)),
                  ('Product', _product(r)),
                  ('Recipient', tStr(r['recipientName']).isEmpty ? '—' : tStr(r['recipientName'])),
                  ('Staff', tNum(r['staffCount']) > 0 ? qtyFmt(r['staffCount']) : '—'),
                ],
                actions: _actions,
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Date', width: 140), TCol('Reason', width: 150), TCol('Product', width: 140), TCol('Quantity', width: 130),
                    TCol('Cost', right: true, width: 110), TCol('Status', width: 100), TCol('Actions', right: true, width: 200),
                  ],
                  rows: [
                    for (final r in items)
                      [
                        Text(fmtDateTime(r['usageDate'], r, _offset), style: const TextStyle(fontWeight: FontWeight.w500)),
                        cellText(_f.label(r['category'])),
                        cellText(_product(r)),
                        cellText(describeRestaurantInternalQty(r)),
                        Align(alignment: Alignment.centerRight, child: Text(_gh(tNum(r['totalCostValue'])))),
                        Align(alignment: Alignment.centerLeft, child: _badge(r['status'])),
                        Wrap(alignment: WrapAlignment.end, children: _actions(r)),
                      ],
                  ],
                ),
                pager: CompactPager(
                  total: visible.length,
                  page: _page,
                  pageSize: _pageSize,
                  onPage: (p) => setState(() => _page = p),
                  onPageSize: (v) => setState(() {
                    _pageSize = v;
                    _page = 1;
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Record internal use / Edit draft.
class _FormDialog extends StatefulWidget {
  const _FormDialog({required this.session, required this.company, required this.products, required this.fmt, required this.flavor, this.editing});
  final Session session;
  final Company company;
  final List<Map> products;
  final FarmMoney fmt;
  final InternalUseFlavor flavor;
  final Map? editing;

  @override
  State<_FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<_FormDialog> {
  final _today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  late String _date = _today;
  String _category = 'StaffWelfare';
  String _itemKey = '';
  bool _staffHelper = true;
  bool _saving = false;
  final _recipient = TextEditingController(), _reason = TextEditingController(), _notes = TextEditingController();
  final _qty = TextEditingController(text: '0'), _cost = TextEditingController(text: '0');
  final _staffCount = TextEditingController(text: '0'), _perStaff = TextEditingController(text: '0');

  int get _editId => tIntOrNull(widget.editing?['internalUsageId']) ?? 0;

  @override
  void initState() {
    super.initState();
    final r = widget.editing;
    if (r != null) {
      final line = rowsOf(r['items']).firstOrNull;
      _date = tStr(r['usageDate']).split('T').first;
      _category = tStr(r['category']);
      _recipient.text = tStr(r['recipientName']);
      _reason.text = tStr(r['reason']);
      _notes.text = tStr(r['notes']);
      // Hotel's lines come back with itemId (withIngredientIds reads it as the stock id).
      if (line != null) {
        _itemKey = _optKey(line['itemType'], line['itemType'] == 'MenuItem' ? line['menuItemId'] : (line['ingredientId'] ?? line['itemId']));
      }
      _qty.text = _plain(tNum(line?['entryQuantity']));
      _cost.text = _plain(tNum(line?['entryUnitCost']));
      _staffHelper = false;
      _staffCount.text = _plain(tNum(r['staffCount']));
      _perStaff.text = _plain(tNum(line?['quantityPerStaff']));
    } else if (widget.products.length == 1) {
      // openCreate: preselect the only product, its cost seeded.
      final only = widget.products.first;
      _itemKey = _optKey(only['itemType'], only['itemId']);
      _cost.text = _plain(_r4(tNum(only['suggestedUnitCost'])));
    }
  }

  @override
  void dispose() {
    for (final c in [_recipient, _reason, _notes, _qty, _cost, _staffCount, _perStaff]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _plain(num v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';
  num _n(TextEditingController c) => num.tryParse(c.text) ?? 0;

  Map? get _product => widget.products.where((p) => _optKey(p['itemType'], p['itemId']) == _itemKey).firstOrNull;
  bool get _isMenu => _product?['itemType'] == 'MenuItem';
  String get _unitLabel => _isMenu ? 'portion' : (tStr(_product?['unit']).isEmpty ? 'unit' : tStr(_product?['unit']));
  String get _entryLabel => _plural(_unitLabel);
  bool get _staffMode => _staffHelper && _isStaff(_category);
  num get _effective => _staffMode ? _r3(_n(_staffCount) * _n(_perStaff)) : _n(_qty);
  num get _total => _r2(_effective * _n(_cost));
  num get _onHand => tNum(_product?['onHand']);
  num get _suggested => tNum(_product?['suggestedUnitCost']);
  bool get _notEnough => _product != null && _effective > _onHand;

  /// Seed the cost from stock history when the item changes.
  void _pick(String? key) => setState(() {
        _itemKey = key ?? '';
        _cost.text = _plain(_r4(tNum(_product?['suggestedUnitCost'])));
      });

  String? _validate() {
    if (_date.isEmpty) return 'Pick the date.';
    if (_date.compareTo(_today) > 0) return 'The date cannot be in the future.';
    if (_category.isEmpty) return 'Pick what the stock was used for.';
    if (_product == null) return 'Pick the product.';
    if (_effective <= 0) return 'Enter a quantity greater than zero.';
    if (_staffMode) {
      if (_n(_staffCount) <= 0) return 'Enter how many staff received it.';
      if (_n(_perStaff) <= 0) return 'Enter how much each staff member received.';
    }
    if (_notEnough) return 'Not enough stock: ${_plain(_onHand)} $_unitLabel available, ${_plain(_effective)} needed.';
    return null;
  }

  Future<void> _save() async {
    final bad = _validate();
    if (bad != null) return trackerToast(context, bad, error: true);
    final p = _product!;
    setState(() => _saving = true);
    final menu = p['itemType'] == 'MenuItem';
    final payload = {
      'usageDate': _date,
      'category': _category,
      'reason': _reason.text.isEmpty ? null : _reason.text,
      'recipientName': _recipient.text.isEmpty ? null : _recipient.text,
      'staffCount': _staffMode ? _n(_staffCount) : null,
      'notes': _notes.text.isEmpty ? null : _notes.text,
      'items': [
        {
          'itemType': tStr(p['itemType']),
          'ingredientId': menu ? null : tIntOrNull(p['itemId']),
          'menuItemId': menu ? tIntOrNull(p['itemId']) : null,
          // Hotel's toApi: itemId = itemId ?? ingredientId.
          if (widget.flavor.itemIdKey) 'itemId': menu ? null : tIntOrNull(p['itemId']),
          'entryQuantity': _effective,
          'entryUnit': _unitLabel,
          'quantityPerStaff': _staffMode ? _n(_perStaff) : null,
          'entryUnitCost': _n(_cost),
        },
      ],
      'farmId': widget.company.farmId,
    };
    final api = widget.session.farmClient;
    final q = '?farmId=${Uri.encodeQueryComponent(widget.company.farmId)}';
    try {
      if (_editId != 0) {
        await api.put('${widget.flavor.api}/$_editId$q', body: payload);
        if (mounted) trackerToast(context, 'Draft updated');
      } else {
        await api.post('${widget.flavor.api}$q', body: payload);
        if (mounted) trackerToast(context, 'Draft saved', description: "Post it when you're ready to move the stock.");
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, "Couldn't save", description: e.message, error: true);
    }
  }

  Widget _choice(bool active, String title, String sub, VoidCallback on) => Expanded(
        child: InkWell(
          onTap: on,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: active ? widget.flavor.soft : Colors.white,
              border: Border.all(color: active ? widget.flavor.accent : TColors.slate200, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TColors.slate900)),
              Text(sub, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
            ]),
          ),
        ),
      );

  Widget _numField(String label, TextEditingController c, {String? hint}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilterLabel(
          label,
          AppInput(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (hint != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(hint, style: const TextStyle(fontSize: 11, color: TColors.slate500))),
      ]);

  Widget _optional(String label, TextEditingController c, String hint) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilterLabel(label, AppInput(controller: c, hintText: hint)),
        const Padding(padding: EdgeInsets.only(top: 4), child: Text('Optional', style: TextStyle(fontSize: 11, color: TColors.slate500))),
      ]);

  @override
  Widget build(BuildContext context) {
    final gh = widget.fmt;
    final p = _product;
    final stock = [for (final x in widget.products) if (x['itemType'] == widget.flavor.stockType) x];
    final menu = [for (final x in widget.products) if (x['itemType'] == 'MenuItem') x];
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Text(_editId != 0 ? 'Edit draft' : 'Record internal use'),
        content: SizedBox(
          width: 640,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('This reduces stock and records the cost. It does not create a sale, a customer balance or a cash transaction.',
                style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            formSection('What was used, and why', restaurantRose, [
              FilterLabel(
                'Date',
                AppDateField(
                  value: businessDateAsDateTime(_date),
                  lastDate: businessDateAsDateTime(_today),
                  onChanged: (d) => setState(() => _date = d == null ? _date : isoDay(d)),
                ),
              ),
              FilterLabel(
                'Reason',
                AppSelect<String>(
                  value: _category,
                  items: [for (final c in widget.flavor.categories) AppSelectItem(value: c, label: widget.flavor.label(c))],
                  onChanged: (v) => setState(() => _category = v ?? _category),
                ),
              ),
              _optional('Who received it', _recipient, widget.flavor.recipientHint),
              _optional('Detail', _reason, 'e.g. Friday staff lunch'),
            ]),
            const SizedBox(height: 12),
            formSection('How much', const Color(0xFF2563EB), [
              if (widget.products.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: const Color(0xFFFDE68A)), borderRadius: BorderRadius.circular(8)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('This company has no products yet.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.amber900)),
                    const SizedBox(height: 4),
                    const Text('Internal Use takes stock off a product, so add one first — then come back and record what was given out.',
                        style: TextStyle(fontSize: 13, color: TColors.amber800)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () {
                        Navigator.pop(context, false);
                        openAppHref(context, widget.session, widget.company, widget.flavor.inventoryHref, label: 'Inventory');
                      },
                      child: const Text('Go to Inventory',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.amber900, decoration: TextDecoration.underline)),
                    ),
                  ]),
                )
              else
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  FilterLabel(
                    'Product',
                    AppSelect<String>(
                      value: _itemKey.isEmpty ? null : _itemKey,
                      hintText: 'Pick a product',
                      items: [
                        if (stock.isNotEmpty) const AppSelectItem(value: '__stock', label: 'Stock items', enabled: false),
                        for (final x in stock) AppSelectItem(value: _optKey(x['itemType'], x['itemId']), label: tStr(x['name'])),
                        if (menu.isNotEmpty) const AppSelectItem(value: '__menu', label: 'Menu items (uses the recipe)', enabled: false),
                        for (final x in menu) AppSelectItem(value: _optKey(x['itemType'], x['itemId']), label: tStr(x['name'])),
                      ],
                      onChanged: _pick,
                    ),
                  ),
                  if (p != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                          _isMenu
                              ? 'Takes its recipe out of stock · enough for ${qtyFmt(_onHand)} portions'
                              : '${qtyFmt(_onHand)} ${_unitLabel.toLowerCase()} in stock',
                          style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                    ),
                ]),
              if (_isStaff(_category))
                FilterLabel(
                  'How do you want to enter it?',
                  Row(children: [
                    _choice(!_staffHelper, 'Total quantity', 'Type one number', () => setState(() => _staffHelper = false)),
                    const SizedBox(width: 8),
                    _choice(_staffHelper, 'Per staff member', 'Staff × amount each', () => setState(() => _staffHelper = true)),
                  ]),
                ),
              if (_staffMode) ...[
                _numField('Number of staff', _staffCount),
                _numField('$_entryLabel each', _perStaff),
              ] else
                _numField('Total ${_entryLabel.toLowerCase()}', _qty),
              _numField('Cost per ${_singular(_unitLabel).toLowerCase()}', _cost,
                  hint: _suggested > 0
                      ? 'Suggested from your stock history — change it if you need to'
                      : 'No purchase history yet — enter what it costs you'),
            ]),
            const SizedBox(height: 12),
            formSection('Check before you save', TColors.slate600, [
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _summary('Coming out of stock', _effective > 0 ? '${qtyFmt(_effective)} ${_entryLabel.toLowerCase()}' : '—',
                    note: _isMenu && _effective > 0 ? 'Its recipe ingredients come out of stock' : null),
                const Divider(height: 1, color: TColors.slate100),
                _summary('Cost recorded', gh(_total)),
                if (_notEnough)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'Not enough stock: only ${qtyFmt(_onHand)} ${_unitLabel.toLowerCase()} available, ${qtyFmt(_effective)} needed.',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.red600),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'Posting reduces stock and records the cost as a non-cash expense. It does not create a sale, a customer balance or any cash movement. Stock expensed when purchased was already charged to Profit & Loss when it was bought, so it is not charged again.',
                    style: TextStyle(fontSize: 11, color: TColors.slate500),
                  ),
                ),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilterLabel('Notes', AppInput(controller: _notes, minLines: 2, maxLines: 4)),
                const Padding(padding: EdgeInsets.only(top: 4), child: Text('Optional', style: TextStyle(fontSize: 11, color: TColors.slate500))),
              ]),
            ]),
          ]),
        ),
        actions: [
          Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: widget.flavor.accent),
              onPressed: _saving || _notEnough ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save draft'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _summary(String label, String value, {String? note}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: TColors.slate500))),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColors.slate900)),
              if (note != null) Text(note, textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
            ]),
          ),
        ]),
      );
}

/// The details dialog: reversal, what was used (with what reached the P&L),
/// who and why, and the history.
class _Detail extends StatelessWidget {
  const _Detail({required this.record, required this.fmt, required this.offset, required this.flavor});
  final Map record;
  final FarmMoney fmt;
  final Duration offset;
  final InternalUseFlavor flavor;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final line = rowsOf(r['items']).firstOrNull;
    Widget card(Widget child, {String? title, bool amber = false}) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: amber ? TColors.amber50 : Colors.white,
            border: Border.all(color: amber ? const Color(0xFFFDE68A) : TColors.slate200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (title != null) ...[
              Text(title.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .5, color: TColors.slate500)),
              const SizedBox(height: 10),
            ],
            child,
          ]),
        );
    Widget? row(String label, Object? value) => tStr(value).isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
              const SizedBox(width: 24),
              Expanded(child: Text(tStr(value), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
            ]),
          );
    Widget? step(String label, Object? who, Object? when, Color dot) => tStr(who).isEmpty && tStr(when).isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
              Text(tStr(when).split('T').first, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
          );
    return AlertDialog(
      scrollable: true,
      backgroundColor: TColors.slate50,
      title: Row(children: [
        Expanded(child: Text(tStr(r['referenceNo']).isEmpty ? 'Internal use' : tStr(r['referenceNo']))),
        _badge(r['status']),
      ]),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${fmtDateTime(r['usageDate'], r, offset)} · ${flavor.label(r['category'])}',
              style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 12),
          if (tStr(r['status']) == 'Reversed') ...[
            card(
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.undo, size: 16, color: TColors.amber700),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Reversed — ${tStr(r['reversalReason']).isEmpty ? 'no reason recorded' : tStr(r['reversalReason'])}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColors.amber900)),
                    Text(fmtInstant(r['reversedAt'], offset), style: const TextStyle(fontSize: 12, color: TColors.amber800)),
                  ]),
                ),
              ]),
              amber: true,
            ),
            const SizedBox(height: 10),
          ],
          card(
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tStr(line?['itemName']).isEmpty ? '-' : tStr(line?['itemName']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Text('${describeRestaurantInternalQty(r)} @ ${fmt(tNum(line?['entryUnitCost']))}',
                      style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                ),
                Text(fmt(tNum(r['totalCostValue'])), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: TColors.slate900)),
              ]),
              if (tStr(r['status']) == 'Posted')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Charged to Profit & Loss now: ${fmt(tNum(r['plCost']))}. The rest was charged when the stock was bought (expense when purchased), or never came through a purchase.',
                    style: const TextStyle(fontSize: 12, color: TColors.slate500),
                  ),
                ),
            ]),
            title: 'What was used',
          ),
          const SizedBox(height: 10),
          card(
            Column(children: [
              ...[
                row('Reason', flavor.label(r['category'])),
                row('Recipient', r['recipientName']),
                row('Staff', tNum(r['staffCount']) > 0 ? tStr(r['staffCount']) : null),
                row('Detail', r['reason']),
                row('Notes', r['notes']),
              ].whereType<Widget>(),
            ]),
            title: 'Who and why',
          ),
          const SizedBox(height: 10),
          card(
            Column(children: [
              ...[
                step('Created', r['createdBy'], r['createdAt'], TColors.slate300),
                step('Posted', r['postedBy'], r['postedAt'], const Color(0xFF10B981)),
                step('Reversed', r['reversedBy'], r['reversedAt'], const Color(0xFFF59E0B)),
              ].whereType<Widget>(),
            ]),
            title: 'History',
          ),
        ]),
      ),
      actions: [OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
