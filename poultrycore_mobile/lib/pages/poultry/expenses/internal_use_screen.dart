import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../money/money_widgets.dart';
import '../money/reconciliation_screen.dart' show ReasonPromptDialog;
import '../reports/report_format.dart';
import '../reports/report_routes.dart' show openAppHref;
import '../sales/balances_logic.dart' show pageSlice;
import '../sales/balances_widgets.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';
import 'deferred_costs_screen.dart' show qtyFmt;

/// Poultry → Expenses → Internal Use, as `app/poultry-internal-use/page.tsx`:
/// eggs, birds, feed or supplies the farm used itself — recorded at cost,
/// never as a sale. A draft is saved first, then posted.

const internalUseCategories = ['StaffWelfare', 'OwnerUse', 'FarmUse', 'Sample', 'Donation', 'QualityTest', 'InternalConsumption', 'Other'];
const _categoryLabels = {
  'StaffWelfare': 'Staff allowance',
  'OwnerUse': 'Owner use',
  'OfficeUse': 'Office use',
  'FarmUse': 'Farm use',
  'Sample': 'Sample / promotion',
  'Donation': 'Donation',
  'QualityTest': 'Quality testing',
  'InternalConsumption': 'Internal consumption',
  'Other': 'Other',
};
String internalUseCategoryLabel(Object? c) => _categoryLabels[tStr(c)] ?? tStr(c);

/// STAFF_BASED_CATEGORIES: entered as staff × amount each.
bool isStaffCategory(Object? c) => tStr(c) == 'StaffWelfare' || tStr(c) == 'OfficeUse';

const internalUseReversalReasons = [
  ('Wrong quantity', 'Wrong quantity'),
  ('Wrong product', 'Wrong product'),
  ('Wrong cost', 'Wrong cost'),
  ('Wrong date', 'Wrong date'),
  ('Wrong recipient', 'Wrong recipient or reason'),
  ('Duplicate entry', 'Duplicate entry'),
  ('Posted by mistake', 'Posted by mistake'),
  ('Stock returned unused', 'Stock returned unused'),
  ('Other', 'Other'),
];

const eggsPerCrate = 30;

num _r2(num n) => (n * 100).round() / 100;
num _r3(num n) => (n * 1000).round() / 1000;
num _r4(num n) => (n * 10000).round() / 10000;

String _singular(String unit) {
  final u = (unit.isEmpty ? 'Egg' : unit).trim();
  return u.toLowerCase().endsWith('s') ? u.substring(0, u.length - 1) : u;
}

String _plural(String unit) {
  final u = unit.trim();
  if (u.isEmpty) return 'Sachets';
  return u.toLowerCase().endsWith('s') ? u : '${u}s';
}

String _unitWord(String unit) => unit.toLowerCase() == 'crate' ? 'Crates' : _plural(unit);

/// describeQty: "3 crates (90 eggs)" or "5 bags".
String describeInternalQty(Map r) {
  final items = rowsOf(r['items']);
  if (items.isEmpty) return '—';
  final line = items.first;
  final entry = '${qtyFmt(line['entryQuantity'])} ${_unitWord(tStr(line['entryUnit']).isEmpty ? 'Egg' : tStr(line['entryUnit'])).toLowerCase()}';
  final f = line['unitsPerEntryUnit'] == null ? 1 : tNum(line['unitsPerEntryUnit']);
  return f > 1 ? '$entry (${qtyFmt(line['stockQuantity'])} eggs)' : entry;
}

/// (bg, fg) of STATUS_BADGE.
(Color, Color) internalUseTone(Object? s) => switch (tStr(s)) {
      'Posted' => (const Color(0xFFDCFCE7), const Color(0xFF15803D)),
      'Reversed' => (TColors.amber100, TColors.amber700),
      _ => (TColors.slate100, TColors.slate700),
    };

Widget _badge(Object? s) {
  final (bg, fg) = internalUseTone(s);
  return TBadge(tStr(s), bg: bg, fg: fg);
}

/// The page's filters: date and search (five keys), status, reason.
List<Map> filterInternalUse(List<Map> rows, {String search = '', String from = '', String to = '', String status = 'ALL', String category = 'ALL'}) {
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

class InternalUseScreen extends StatefulWidget {
  const InternalUseScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<InternalUseScreen> createState() => _InternalUseScreenState();
}

class _InternalUseScreenState extends State<InternalUseScreen> {
  List<Map> _items = [], _products = [];
  bool _loading = true;
  final _search = TextEditingController();
  String _from = '', _to = '', _status = 'ALL', _category = 'ALL';
  int _page = 1, _pageSize = 10, _lastTotal = -1;
  FarmMoney _gh = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  String get _q => 'farmId=${Uri.encodeQueryComponent(_farmId)}';
  String get _me => Uri.encodeQueryComponent(widget.session.tokens.userId ?? '');

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

  /// Records and products load separately; either failing toasts on its own.
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = rowsOf(await _api.get('/api/Poultry/internal-usage', query: {'farmId': _farmId}));
      if (mounted) setState(() => _items = r);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, "Couldn't load internal use records", description: e.message, error: true);
    }
    try {
      final p = rowsOf(await _api.get('/api/Poultry/products', query: {'farmId': _farmId}));
      if (mounted) setState(() => _products = p);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, "Couldn't load products", description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  int _id(Map r) => tIntOrNull(r['poultryInternalUsageId']) ?? 0;

  Future<void> _openForm([Map? editing]) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => InternalUseFormDialog(session: widget.session, company: widget.company, products: _products, fmt: _gh, editing: editing),
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
            style: destructive ? FilledButton.styleFrom(backgroundColor: TColors.red600) : null,
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
            ? '${describeInternalQty(r)} comes back out of stock and ${_gh(tNum(r['totalCostValue']))} is booked as a non-cash expense again. The reversal stays in the stock history.'
            : '${describeInternalQty(r)} comes out of stock and ${_gh(tNum(r['totalCostValue']))} is booked as a non-cash expense. No sale and no cash movement is created.',
        action: again ? 'Post again' : 'Post',
        run: () async {
          await _api.post('/api/Poultry/internal-usage/${_id(r)}/post?$_q&postedBy=$_me');
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
          await _api.delete('/api/Poultry/internal-usage/${_id(r)}?$_q&userId=$_me');
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
      await _api.post('/api/Poultry/internal-usage/${_id(r)}/reverse?$_q&reversedBy=$_me',
          body: {'reason': reason, 'userId': widget.session.tokens.userId});
      if (mounted) trackerToast(context, 'Reversed', description: 'Stock restored and the expense cancelled.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, "Couldn't reverse", description: e.message, error: true);
    }
  }

  Future<void> _view(Map r) => showDialog<void>(context: context, builder: (_) => _InternalUseDetail(record: r, fmt: _gh, offset: _offset));

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

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-internal-use');
    final visible = filterInternalUse(_items, search: _search.text, from: _from, to: _to, status: _status, category: _category);
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
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Internal Use')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.remove_shopping_cart_outlined, size: 24, color: Color(0xFF0284C7)),
              SizedBox(width: 8),
              Expanded(child: Text('Internal Use', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900))),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Eggs, birds, feed or supplies used by the farm — given to staff, taken by the owner, donated, sampled or tested. Recorded at cost, never as a sale.',
              style: TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFF0F9FF), border: Border.all(color: const Color(0xFFBAE6FD)), borderRadius: BorderRadius.circular(6)),
              child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, size: 16, color: TColors.sky900),
                SizedBox(width: 6),
                Expanded(
                  child: Text('Posting writes a stock movement, updates inventory and books a non-cash expense.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.sky900)),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: () => _openForm(), icon: const Icon(Icons.add, size: 18), label: const Text('Record internal use')),
            if (!_loading && _products.isEmpty) ...[
              const SizedBox(height: 12),
              _noProducts(),
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
                    for (final c in internalUseCategories) AppSelectItem(value: c, label: internalUseCategoryLabel(c)),
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
                stripeBlue: true,
                items: pageRows,
                keyOf: (r) => '${_id(r)}',
                primary: (r) => internalUseCategoryLabel(r['category']),
                secondary: (r) => fmtDateTime(r['usageDate'], r, _offset),
                trailing: (r) => Padding(padding: const EdgeInsets.only(left: 6), child: _badge(r['status'])),
                highlights: (r) => [
                  Highlight('Quantity', describeInternalQty(r), accent: Accent.blue),
                  Highlight('Cost', _gh(tNum(r['totalCostValue'])), accent: Accent.violet),
                ],
                details: (r) {
                  final items = rowsOf(r['items']);
                  return [
                    ('Date', fmtDateTime(r['usageDate'], r, _offset)),
                    ('Product', items.isEmpty || tStr(items.first['productName']).isEmpty ? '—' : tStr(items.first['productName'])),
                    ('Recipient', tStr(r['recipientName']).isEmpty ? '—' : tStr(r['recipientName'])),
                    ('Staff', tNum(r['staffCount']) > 0 ? qtyFmt(r['staffCount']) : '—'),
                  ];
                },
                actions: _actions,
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Date', width: 140), TCol('Reason', width: 140), TCol('Product', width: 130), TCol('Quantity', width: 170),
                    TCol('Cost', right: true, width: 110), TCol('Status', width: 100), TCol('Actions', right: true, width: 200),
                  ],
                  rows: [
                    for (final r in items)
                      [
                        Text(fmtDateTime(r['usageDate'], r, _offset), style: const TextStyle(fontWeight: FontWeight.w500)),
                        cellText(internalUseCategoryLabel(r['category'])),
                        cellText(rowsOf(r['items']).isEmpty ? '—' : tStr(rowsOf(r['items']).first['productName'])),
                        cellText(describeInternalQty(r)),
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

  Widget _noProducts() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: const Color(0xFFFDE68A)), borderRadius: BorderRadius.circular(8)),
        child: Wrap(children: [
          const Text('No products in this company yet. ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.amber900)),
          const Text('Internal Use takes stock off a product, so add one before recording anything. ', style: TextStyle(fontSize: 13, color: TColors.amber800)),
          InkWell(
            onTap: () => openAppHref(context, widget.session, widget.company, '/poultry-products', label: 'Products'),
            child: const Text('Go to Products', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.amber900, decoration: TextDecoration.underline)),
          ),
        ]),
      );
}

/// Record internal use / Edit draft.
class InternalUseFormDialog extends StatefulWidget {
  const InternalUseFormDialog({super.key, required this.session, required this.company, required this.products, required this.fmt, this.editing});
  final Session session;
  final Company company;
  final List<Map> products;
  final FarmMoney fmt;
  final Map? editing;

  @override
  State<InternalUseFormDialog> createState() => _InternalUseFormDialogState();
}

class _InternalUseFormDialogState extends State<InternalUseFormDialog> {
  final _today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  late String _date = _today;
  String _category = 'StaffWelfare';
  int _productId = 0;
  String _entryUnit = 'Crate';
  bool _staffHelper = true;
  num _suggested = 0;
  bool _saving = false;
  final _recipient = TextEditingController(), _reason = TextEditingController(), _notes = TextEditingController();
  final _qty = TextEditingController(text: '0'), _cost = TextEditingController(text: '0');
  final _staffCount = TextEditingController(text: '0'), _perStaff = TextEditingController(text: '0');

  int get _editId => tIntOrNull(widget.editing?['poultryInternalUsageId']) ?? 0;

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
      _productId = tIntOrNull(line?['poultryProductId']) ?? 0;
      _entryUnit = tStr(line?['entryUnit']).isEmpty ? 'Crate' : tStr(line?['entryUnit']);
      _qty.text = _plain(tNum(line?['entryQuantity']));
      _cost.text = _plain(tNum(line?['entryUnitCost']));
      _staffHelper = false;
      _staffCount.text = _plain(tNum(r['staffCount']));
      _perStaff.text = _plain(tNum(line?['quantityPerStaff']));
    } else {
      // openCreate: preselect the only product, or the only raw-egg product.
      final ps = widget.products;
      final eggs = [for (final p in ps) if (p['isRawEggProduct'] == true) p];
      final only = ps.length == 1 ? ps.first : (eggs.length == 1 ? eggs.first : null);
      _productId = tIntOrNull(only?['poultryProductId']) ?? 0;
      _entryUnit = only != null && only['isRawEggProduct'] != true ? (tStr(only['unit']).isEmpty ? 'Unit' : tStr(only['unit'])) : 'Crate';
    }
    _fixUnit();
    _suggest();
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

  Map? get _product => widget.products.where((p) => tIntOrNull(p['poultryProductId']) == _productId).firstOrNull;
  bool get _rawEgg => _product?['isRawEggProduct'] == true;

  /// A non-egg product cannot be entered in crates: switch to its own unit.
  void _fixUnit() {
    final p = _product;
    if (p != null && !_rawEgg && _entryUnit == 'Crate') _entryUnit = tStr(p['unit']).isEmpty ? 'Unit' : tStr(p['unit']);
  }

  /// The suggested cost per entry unit, from stock history.
  Future<void> _suggest() async {
    if (_productId == 0) return;
    final pid = _productId, unit = _entryUnit;
    try {
      final r = await widget.session.farmClient.get('/api/Poultry/internal-usage/suggested-cost',
          query: {'farmId': widget.company.farmId, 'poultryProductId': '$pid', 'entryUnit': unit});
      if (!mounted || pid != _productId || unit != _entryUnit) return;
      final c = r is Map ? tNum(r['unitCost']) : 0;
      setState(() {
        _suggested = c;
        _cost.text = _plain(_r4(c));
      });
    } on ApiException {
      // Silent, as the web: the cost stays whatever it was.
    }
  }

  bool get _staffMode => _staffHelper && isStaffCategory(_category);
  String get _entryLabel => _entryUnit == 'Crate' ? 'Crates' : _plural(_entryUnit.isEmpty ? 'Egg' : _entryUnit);
  int get _factor => _entryUnit.toLowerCase() == 'crate' ? eggsPerCrate : 1;
  num get _effective => _staffMode ? _r3(_n(_staffCount) * _n(_perStaff)) : _n(_qty);
  num get _base => _r3(_effective * _factor);
  num get _total => _r2(_effective * _n(_cost));
  num get _onHand => tNum(_product?['stockOnHand']);
  String get _baseUnit => tStr(_product?['unit']).isEmpty ? 'unit' : tStr(_product?['unit']);
  bool get _notEnough => _productId > 0 && _base > _onHand;

  String? _validate() {
    if (_date.isEmpty) return 'Pick the date.';
    if (_date.compareTo(_today) > 0) return 'The date cannot be in the future.';
    if (_category.isEmpty) return 'Pick what the stock was used for.';
    if (_productId == 0) return 'Pick the product.';
    if (_effective <= 0) return 'Enter a quantity greater than zero.';
    if (_staffMode) {
      if (_n(_staffCount) <= 0) return 'Enter how many staff received it.';
      if (_n(_perStaff) <= 0) return 'Enter how much each staff member received.';
    }
    if (_notEnough) return 'Not enough stock: ${_plain(_onHand)} $_baseUnit available, ${_plain(_base)} needed.';
    return null;
  }

  Future<void> _save() async {
    final bad = _validate();
    if (bad != null) return trackerToast(context, bad, error: true);
    setState(() => _saving = true);
    final payload = {
      'usageDate': _date,
      'category': _category,
      'reason': _reason.text.isEmpty ? null : _reason.text,
      'recipientName': _recipient.text.isEmpty ? null : _recipient.text,
      'staffCount': _staffMode ? _n(_staffCount) : null,
      'notes': _notes.text.isEmpty ? null : _notes.text,
      'items': [
        {
          'poultryProductId': _productId,
          'entryQuantity': _effective,
          'entryUnit': _entryUnit,
          'quantityPerStaff': _staffMode ? _n(_perStaff) : null,
          'entryUnitCost': _n(_cost),
          'eggsPerCrate': eggsPerCrate,
        },
      ],
      'farmId': widget.company.farmId,
      'userId': widget.session.tokens.userId,
    };
    final api = widget.session.farmClient;
    try {
      if (_editId != 0) {
        await api.put('/api/Poultry/internal-usage/$_editId', body: {...payload, 'poultryInternalUsageId': _editId});
        if (mounted) trackerToast(context, 'Draft updated');
      } else {
        await api.post('/api/Poultry/internal-usage', body: {...payload, 'createdBy': widget.session.tokens.userId});
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
              color: active ? const Color(0xFFF0F9FF) : Colors.white,
              border: Border.all(color: active ? const Color(0xFF0EA5E9) : TColors.slate200, width: 2),
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

  @override
  Widget build(BuildContext context) {
    final gh = widget.fmt;
    final p = _product;
    final costHint = _entryUnit == 'Crate' && _n(_cost) > 0
        ? '= ${gh(_r4(_n(_cost) / eggsPerCrate))} per egg'
        : _suggested > 0
            ? 'Suggested from your stock history — change it if you need to'
            : 'No purchase history yet — enter what it costs you';
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
            formSection('What was used, and why', const Color(0xFF0284C7), [
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
                  items: [for (final c in internalUseCategories) AppSelectItem(value: c, label: internalUseCategoryLabel(c))],
                  onChanged: (v) => setState(() => _category = v ?? _category),
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilterLabel('Who received it', AppInput(controller: _recipient, hintText: 'e.g. Production team')),
                const Padding(padding: EdgeInsets.only(top: 4), child: Text('Optional', style: TextStyle(fontSize: 11, color: TColors.slate500))),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilterLabel('Detail', AppInput(controller: _reason, hintText: 'e.g. Friday staff allowance')),
                const Padding(padding: EdgeInsets.only(top: 4), child: Text('Optional', style: TextStyle(fontSize: 11, color: TColors.slate500))),
              ]),
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
                        openAppHref(context, widget.session, widget.company, '/poultry-products', label: 'Products');
                      },
                      child: const Text('Go to Products',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.amber900, decoration: TextDecoration.underline)),
                    ),
                  ]),
                )
              else
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  FilterLabel(
                    'Product',
                    AppSelect<String>(
                      value: _productId == 0 ? null : '$_productId',
                      hintText: 'Pick a product',
                      items: [for (final pr in widget.products) AppSelectItem(value: tStr(pr['poultryProductId']), label: tStr(pr['name']))],
                      onChanged: (v) {
                        setState(() {
                          _productId = int.tryParse(v ?? '') ?? 0;
                          _fixUnit();
                        });
                        _suggest();
                      },
                    ),
                  ),
                  if (p != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${qtyFmt(_onHand)} ${_baseUnit.toLowerCase()} in stock${_rawEgg ? ' · 1 crate = $eggsPerCrate eggs' : ''}',
                          style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                    ),
                ]),
              if (_rawEgg)
                FilterLabel(
                  'Given out as',
                  Row(children: [
                    _choice(_entryUnit != 'Crate', 'Eggs', 'Single eggs', () {
                      if (_entryUnit != 'Egg') setState(() => _entryUnit = 'Egg');
                      _suggest();
                    }),
                    const SizedBox(width: 8),
                    _choice(_entryUnit == 'Crate', 'Crates', '1 crate = $eggsPerCrate eggs', () {
                      if (_entryUnit != 'Crate') setState(() => _entryUnit = 'Crate');
                      _suggest();
                    }),
                  ]),
                ),
              if (isStaffCategory(_category))
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
              _numField('Cost per ${_singular(_entryUnit).toLowerCase()}', _cost, hint: costHint),
            ]),
            const SizedBox(height: 12),
            formSection('Check before you save', TColors.slate600, [
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _summary('Coming out of stock', _effective > 0 ? '${qtyFmt(_effective)} ${_entryLabel.toLowerCase()}' : '—',
                    note: _factor > 1 && _effective > 0 ? '${qtyFmt(_base)} eggs' : null),
                const Divider(height: 1, color: TColors.slate100),
                _summary('Cost recorded', gh(_total)),
                if (_notEnough)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'Not enough stock: only ${qtyFmt(_onHand)} ${_baseUnit.toLowerCase()} available, ${qtyFmt(_base)} needed.',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.red600),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'Posting reduces stock and records the cost as a non-cash expense. It does not create a sale, a customer balance or any cash movement.',
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
          OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: _saving || _notEnough ? null : _save, child: Text(_saving ? 'Saving…' : 'Save draft')),
        ],
      ),
    );
  }

  Widget _summary(String label, String value, {String? note}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: TColors.slate500))),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColors.slate900)),
            if (note != null) Text(note, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
          ]),
        ]),
      );
}

/// The details dialog: reversal, what was used, who and why, and the history.
class _InternalUseDetail extends StatelessWidget {
  const _InternalUseDetail({required this.record, required this.fmt, required this.offset});
  final Map record;
  final FarmMoney fmt;
  final Duration offset;

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
          Text('${fmtDateTime(r['usageDate'], r, offset)} · ${internalUseCategoryLabel(r['category'])}', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
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
              Text(tStr(line?['productName']).isEmpty ? '-' : tStr(line?['productName']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Text('${describeInternalQty(r)} @ ${fmt(tNum(line?['entryUnitCost']))}', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                ),
                Text(fmt(tNum(r['totalCostValue'])), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: TColors.slate900)),
              ]),
            ]),
            title: 'What was used',
          ),
          const SizedBox(height: 10),
          card(
            Column(children: [
              ...[
                row('Reason', internalUseCategoryLabel(r['category'])),
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
