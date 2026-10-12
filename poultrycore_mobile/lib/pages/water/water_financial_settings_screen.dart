import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';

/// Water → Setup → Company → Financial Settings ("Cost Recognition"), as
/// `app/water-financial-settings/page.tsx`: when packaging costs and when
/// treatment chemical costs reach Profit & Loss, an optional future start
/// date, and the per-item exceptions table.
///
/// Unlike Poultry's, Expense-when-consumed is locked until the server says
/// `deferralAvailable` — shown disabled with the reason, never hidden. The web
/// also gates view/edit on water.financial-settings.*; the mobile app has no
/// permission flags yet, so it behaves as for an editor.
class WaterFinancialSettingsScreen extends StatefulWidget {
  const WaterFinancialSettingsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<WaterFinancialSettingsScreen> createState() => _WaterFinancialSettingsScreenState();
}

// lib/water/cost-recognition.ts
const _purchased = 'EXPENSE_WHEN_PURCHASED';
const _consumed = 'EXPENSE_WHEN_CONSUMED';
const _methods = [_purchased, _consumed];
String _label(String m) => m == _consumed ? 'Expense when consumed' : 'Expense when purchased';
String _short(Object? m) => m == _consumed ? 'On use' : 'On purchase';
const _help = {
  _purchased: 'The purchase cost is recognised in Profit & Loss straight away. Inventory quantity is still '
      'tracked, and using the item later does not create another expense.',
  _consumed: 'The purchase is held as inventory value first. The cost reaches Profit & Loss later, as the '
      'item is used in production.',
};
const _packagingHint = {
  _purchased: 'Simpler. Suits companies that buy film and bags often and use them quickly.',
  _consumed: 'More precise. Packaging costs affect Profit & Loss as production draws the stock.',
};
const _treatmentHint = {
  _purchased: 'Simpler. Recognise the cost when you buy, while still tracking what is left.',
  _consumed: 'More precise. Recognise the cost as recorded usage reduces stock.',
};
const _groupCategories = {
  'Packaging': ['PackagingRoll', 'SachetFilm', 'OuterBag'],
  'Treatment': ['Chemical'],
  'Unconfigured': ['Filter', 'UVLamp', 'SparePart', 'Fuel', 'CleaningSupply', 'Other'],
};
const _changeWarning = 'This applies to new purchases from now on. Purchases already recorded keep the '
    'treatment they were created with, so past reports do not change.';
const _deferralUnavailable = 'Expense-when-consumed is not available for Water yet. It needs the '
    'consumption-recognition work, which tracks a purchase\'s cost through production and charges it as the '
    'stock is used. Until that is in place, choosing it would leave the cost recognised at purchase AND again '
    'at consumption, so the setting is locked to expense-when-purchased.';
const _deferralFuture = 'Once available, a deferred purchase will hold its cost as inventory value and reach '
    'Profit & Loss as you record production drawing the stock, so nothing is expensed twice.';

class _WaterFinancialSettingsScreenState extends State<WaterFinancialSettingsScreen> {
  Map? _saved;
  List<Map<String, dynamic>> _items = const [];
  int? _savingItem;
  bool _showAll = false;
  String _packaging = _purchased;
  String _treatment = _purchased;
  DateTime? _from;
  bool _loading = true;
  bool _saving = false;

  String get _farm => Uri.encodeComponent(widget.company.farmId);
  String get _path => '/api/Water/financial-settings/cost-recognition?farmId=$_farm';
  String get _itemsPath => '/api/Water/financial-settings/items?farmId=$_farm';

  /// The server owns this; false while loading so the option is never
  /// offered and then withdrawn.
  bool get _deferralAvailable => _saved?['deferralAvailable'] == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _day(DateTime? d) => d == null
      ? ''
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _savedDay(Map? s) => '${s?['effectiveFromDate'] ?? ''}'.split('T').first;

  void _apply(Map s) {
    _saved = s;
    _packaging = '${s['packagingCostRecognitionMethod'] ?? _purchased}';
    _treatment = '${s['treatmentCostRecognitionMethod'] ?? _purchased}';
    _from = DateTime.tryParse(_savedDay(s));
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<List<Map<String, dynamic>>> _readItems() async {
    try {
      final res = await widget.session.farmClient.get(_itemsPath);
      return [
        for (final r in (res is List ? res : const []))
          if (r is Map) Map<String, dynamic>.from(r),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await widget.session.farmClient.get(_path);
      final items = await _readItems();
      if (s is Map) _apply(s);
      _items = items;
    } on ApiException catch (e) {
      if (mounted) _snack('Could not load financial settings. ${e.message}');
    }
    if (mounted) setState(() => _loading = false);
  }

  bool get _dirty {
    final s = _saved;
    if (s == null) return false;
    return _packaging != '${s['packagingCostRecognitionMethod']}' ||
        _treatment != '${s['treatmentCostRecognitionMethod']}' ||
        _day(_from) != _savedDay(s);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final s = await widget.session.farmClient.put(_path, body: {
        'packagingCostRecognitionMethod': _packaging,
        'treatmentCostRecognitionMethod': _treatment,
        'effectiveFromDate': _from == null ? null : _day(_from),
        'farmId': widget.company.farmId,
        'updatedBy': widget.session.tokens.userId,
      });
      if (!mounted) return;
      setState(() {
        if (s is Map) _apply(s);
      });
      _snack('Cost recognition saved. New purchases from now on use these settings. Existing purchases are unchanged.');
      // The resolved item view moves with the company default.
      final items = await _readItems();
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) _snack('Could not save. ${e.message}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setOverride(int itemId, String? value) async {
    setState(() => _savingItem = itemId);
    try {
      final row = await widget.session.farmClient.put(
        '/api/Water/financial-settings/items/$itemId/cost-recognition?farmId=$_farm',
        body: {
          'farmId': widget.company.farmId,
          'costRecognitionOverride': value,
          'updatedBy': widget.session.tokens.userId,
        },
      );
      if (!mounted) return;
      setState(() {
        _items = [
          for (final i in _items)
            if ('${i['waterRawMaterialItemId']}' == '$itemId' && row is Map) {...i, ...row} else i,
        ];
      });
    } on ApiException catch (e) {
      if (mounted) _snack('Could not change this item. ${e.message}');
    } finally {
      if (mounted) setState(() => _savingItem = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/water-financial-settings');
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Cost Recognition')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
              children: [
                Text(
                  'Choose when inventory costs affect Profit & Loss. Physical stock is tracked either way — '
                  'this only decides when a cost counts as a cost.',
                  style: TextStyle(fontSize: 13, color: tokens.mutedForeground),
                ),
                const SizedBox(height: 12),
                if (!_deferralAvailable) ...[
                  const _Note(
                    color: Color(0xFFF1F5F9), // slate-100
                    border: Color(0xFFCBD5E1), // slate-300
                    fg: Color(0xFF334155), // slate-700
                    icon: Icons.lock_outline,
                    title: 'Expense-when-consumed is not available yet',
                    text: _deferralUnavailable,
                  ),
                  const SizedBox(height: 12),
                ],
                // Never present a default as though somebody chose it.
                if (_saved?['isConfigured'] != true) ...[
                  const _Note(
                    color: Color(0xFFF0F9FF), // sky-50
                    border: Color(0xFFBAE6FD), // sky-200
                    fg: Color(0xFF0C4A6E), // sky-900
                    icon: Icons.info_outline,
                    text: 'Nobody has set this up yet, so both are on the standard treatment: costs reach '
                        'Profit & Loss as you pay for them. Nothing changes until you save something '
                        'different here.',
                  ),
                  const SizedBox(height: 12),
                ],
                _MethodSection(
                  icon: const Icon(Icons.inventory_2_outlined, color: Color(0xFF0284C7)),
                  title: 'Packaging Materials',
                  blurb: 'The film, rolls and bags a sachet or bottle physically consumes.',
                  categories: _groupCategories['Packaging']!,
                  value: _packaging,
                  hints: _packagingHint,
                  deferralAvailable: _deferralAvailable,
                  onChanged: (m) => setState(() => _packaging = m),
                ),
                const SizedBox(height: 12),
                _MethodSection(
                  icon: const Icon(Icons.science_outlined, color: Color(0xFF059669)),
                  title: 'Treatment Chemicals',
                  blurb: 'Independent of the packaging setting above — one can defer while the other does not.',
                  categories: _groupCategories['Treatment']!,
                  value: _treatment,
                  hints: _treatmentHint,
                  deferralAvailable: _deferralAvailable,
                  onChanged: (m) => setState(() => _treatment = m),
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Not covered by either setting', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final c in _groupCategories['Unconfigured']!) _Chip(c, outline: true),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        'These always reach Profit & Loss when you buy them, whatever the settings above say. '
                        'Filter and UVLamp are excluded on purpose — they are periodic replacements, and many '
                        'companies record them as maintenance or on the Asset Register instead. Any single item '
                        'can still be changed on its own in the table below.',
                        style: TextStyle(fontSize: 13, color: tokens.mutedForeground),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Start from (optional)', style: TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: AppDateField(
                              value: _from,
                              hintText: 'Apply immediately',
                              // A past date is refused, as on the web.
                              firstDate: DateTime(now.year, now.month, now.day),
                              onChanged: (d) => setState(() => _from = d),
                            ),
                          ),
                          if (_from != null)
                            IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() => _from = null),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Leave blank to apply immediately. A future date holds the change until then. A past '
                        'date is refused — purchases already recorded keep the treatment they were created '
                        'with, so backdating could not change them anyway.',
                        style: TextStyle(fontSize: 12, color: tokens.mutedForeground),
                      ),
                      if (_saved?['isConfigured'] == true) ...[
                        const Divider(height: 20),
                        Text(
                          'Last changed'
                          '${_saved?['updatedAt'] != null ? ' on ${'${_saved!['updatedAt']}'.replaceFirst('T', ' ').split('.').first}' : ''}'
                          '${_saved?['updatedBy'] != null ? ' by ${_saved!['updatedBy']}' : ''}.',
                          style: TextStyle(fontSize: 12, color: tokens.mutedForeground),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_dirty) ...[
                  const SizedBox(height: 12),
                  const _Note(
                    color: Color(0xFFFFFBEB), // amber-50
                    border: Color(0xFFFDE68A), // amber-200
                    fg: Color(0xFF78350F), // amber-900
                    icon: Icons.warning_amber_rounded,
                    text: _changeWarning,
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: _saving ? 'Saving…' : 'Save changes',
                        icon: Icons.save_outlined,
                        size: AppButtonSize.lg,
                        fullWidth: true,
                        busy: _saving,
                        onPressed: !_dirty || _saving ? null : _save,
                      ),
                    ),
                    if (_dirty) ...[
                      const SizedBox(width: 12),
                      AppButton(
                        label: 'Discard',
                        variant: AppButtonVariant.ghost,
                        size: AppButtonSize.lg,
                        onPressed: _saving ? null : _load,
                      ),
                    ],
                  ],
                ),
                ..._itemTable(context),
              ],
            ),
    );
  }

  /// The per-item exceptions. Hidden when there are no active items.
  List<Widget> _itemTable(BuildContext context) {
    final tokens = context.tokens;
    final active = [for (final i in _items) if (i['isActive'] == true) i];
    if (active.isEmpty) return const [];
    final overridden = [
      for (final i in active)
        if (i['costRecognitionOverride'] != null && '${i['costRecognitionOverride']}'.isNotEmpty) i,
    ];
    final rows = _showAll ? active : overridden;
    return [
      const SizedBox(height: 16),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title and toggle wrap onto two lines on a phone rather than
            // squeezing the title to one letter a line.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                const Text('Per-item exceptions', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                AppButton(
                  label: _showAll ? 'Show exceptions only' : 'Show all ${active.length}',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  onPressed: () => setState(() => _showAll = !_showAll),
                ),
              ],
            ),
            Text(
              'An item can be treated differently from its category. This is the only way to defer something '
              'in an uncovered category — or to keep one item on purchase while the rest of its category defers.',
              style: TextStyle(fontSize: 13, color: tokens.mutedForeground),
            ),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('No item overrides. Every item follows its category.',
                    style: TextStyle(fontSize: 13, color: tokens.mutedForeground)),
              )
            else
              for (final i in rows) _itemRow(context, i),
          ],
        ),
      ),
    ];
  }

  Widget _itemRow(BuildContext context, Map<String, dynamic> i) {
    final tokens = context.tokens;
    final id = int.tryParse('${i['waterRawMaterialItemId']}') ?? 0;
    final isOverride = i['costRecognitionSource'] == 'ItemOverride';
    final group = '${i['costRecognitionCategoryGroup'] ?? ''}';
    final busy = _savingItem == id;
    final small = TextStyle(fontSize: 12, color: tokens.mutedForeground);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${i['itemName'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Category', style: small),
                const SizedBox(height: 2),
                _Chip('${i['category'] ?? ''}', outline: true),
                const SizedBox(height: 2),
                Text(group == 'Unconfigured' ? 'No company setting' : 'Follows $group', style: small),
              ]),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Treated as', style: small),
                const SizedBox(height: 2),
                _Chip(_short(i['effectiveCostRecognitionMethod']), solid: isOverride),
                const SizedBox(height: 2),
                Text(isOverride ? 'Set on this item' : 'Company default', style: small),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : isOverride
                    ? AppButton(
                        label: 'Clear',
                        variant: AppButtonVariant.ghost,
                        size: AppButtonSize.sm,
                        onPressed: () => _setOverride(id, null),
                      )
                    : Wrap(spacing: 6, children: [
                        AppButton(
                          label: 'On purchase',
                          variant: AppButtonVariant.outline,
                          size: AppButtonSize.sm,
                          onPressed: () => _setOverride(id, _purchased),
                        ),
                        // Locked for the same reason the settings are.
                        Tooltip(
                          message: _deferralAvailable ? '' : _deferralUnavailable,
                          child: AppButton(
                            label: 'On use',
                            variant: AppButtonVariant.outline,
                            size: AppButtonSize.sm,
                            onPressed: _deferralAvailable ? () => _setOverride(id, _consumed) : null,
                          ),
                        ),
                      ]),
          ),
        ],
      ),
    );
  }
}

/// One choice: two radio cards, the selected one ringed in sky. The deferred
/// card is disabled, with its reason, until the server allows it.
class _MethodSection extends StatelessWidget {
  const _MethodSection({
    required this.icon,
    required this.title,
    required this.blurb,
    required this.categories,
    required this.value,
    required this.hints,
    required this.deferralAvailable,
    required this.onChanged,
  });
  final Widget icon;
  final String title;
  final String blurb;
  final List<String> categories;
  final String value;
  final Map<String, String> hints;
  final bool deferralAvailable;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            icon,
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 4),
          Text(blurb, style: TextStyle(fontSize: 13, color: tokens.mutedForeground)),
          const SizedBox(height: 8),
          // Which categories this actually governs. The commonest question.
          Wrap(spacing: 6, runSpacing: 6, children: [for (final c in categories) _Chip(c)]),
          const SizedBox(height: 10),
          for (final m in _methods) ...[
            Builder(builder: (context) {
              final selected = value == m;
              final locked = m == _consumed && !deferralAvailable;
              return Opacity(
                opacity: locked ? 0.6 : 1,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: locked ? null : () => onChanged(m),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFF0F9FF) : null, // sky-50
                      border: Border.all(color: selected ? const Color(0xFF0EA5E9) : tokens.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                            size: 18, color: selected ? const Color(0xFF0284C7) : tokens.mutedForeground),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                Text(_label(m), style: const TextStyle(fontWeight: FontWeight.w500)),
                                if (m == _purchased) const AppBadge(label: 'Current standard'),
                                if (locked) const _Chip('🔒 Not available yet', outline: true),
                              ]),
                              const SizedBox(height: 2),
                              Text(hints[m]!, style: TextStyle(fontSize: 12, color: tokens.cardForeground)),
                              const SizedBox(height: 4),
                              Text(locked ? _deferralFuture : _help[m]!,
                                  style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// A small badge: secondary (grey fill), outline, or solid (primary).
class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.outline = false, this.solid = false});
  final String text;
  final bool outline;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: solid ? const Color(0xFF171717) : (outline ? null : tokens.muted),
        border: outline ? Border.all(color: tokens.border) : null,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 12, color: solid ? Colors.white : tokens.cardForeground)),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({
    required this.color,
    required this.border,
    required this.fg,
    required this.icon,
    required this.text,
    this.title,
  });
  final Color color;
  final Color border;
  final Color fg;
  final IconData icon;
  final String text;
  final String? title;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (title != null) ...[
                  Text(title!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
                  const SizedBox(height: 2),
                ],
                Text(text, style: TextStyle(fontSize: 13, color: fg)),
              ]),
            ),
          ],
        ),
      );
}
