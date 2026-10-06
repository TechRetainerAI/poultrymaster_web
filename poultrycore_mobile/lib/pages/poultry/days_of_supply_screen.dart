import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../lookup_loader.dart';
import '../shared/business_dates.dart';
import '../web_page_screen.dart';

/// Poultry → Tools → Days of Supply, as `app/poultry-days-of-supply/page.tsx`
/// with the wording of `lib/inventory/days-of-supply.ts`: every raw material,
/// its stock, how much is actually used per day, how long that lasts and an
/// estimated stock-out date, worst first. GET `/Poultry/stock-supply`.
class DaysOfSupplyScreen extends StatefulWidget {
  const DaysOfSupplyScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<DaysOfSupplyScreen> createState() => _DaysOfSupplyScreenState();
}

const _lookbacks = [7, 14, 30];
const _actionable = {'Negative', 'OutOfStock', 'Critical', 'Warning'};

/// supplyStatusStyle: (label, background, foreground).
(String, Color, Color) _statusStyle(String s) => switch (s) {
      'Negative' => ('Negative stock', const Color(0xFFFFE4E6), const Color(0xFFBE123C)),
      'OutOfStock' => ('Out of stock', const Color(0xFFFFE4E6), const Color(0xFFBE123C)),
      'Critical' => ('Critical', const Color(0xFFFFE4E6), const Color(0xFFBE123C)),
      'Warning' => ('Warning', const Color(0xFFFEF3C7), const Color(0xFF92400E)),
      'Healthy' => ('Healthy', const Color(0xFFD1FAE5), const Color(0xFF047857)),
      'InsufficientHistory' => ('Not enough history', const Color(0xFFF1F5F9), const Color(0xFF475569)),
      _ => ('No recent usage', const Color(0xFFF1F5F9), const Color(0xFF475569)),
    };

num? _n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');

String _qty(Object? n, Object? unit, [int digits = 1]) {
  final s = fmtNum(_n(n), digits);
  final u = '${unit ?? ''}';
  return s == '—' ? s : '$s${u.isNotEmpty ? ' $u' : ''}';
}

/// daysText.
String _days(Map r) => switch ('${r['status']}') {
      'Negative' => 'Stock is below zero — correct the count',
      'OutOfStock' => 'Out of stock',
      'InsufficientHistory' => 'Not enough history yet',
      'NoRecentUsage' => 'No recent usage',
      _ => () {
          final d = _n(r['daysOfSupply']);
          if (d == null) return '—';
          return '${fmtNum(d)} day${d == 1 ? '' : 's'} remaining';
        }(),
    };

/// stockoutText.
String? _stockout(Map r) {
  if (r['status'] == 'Negative') return null;
  final d = toBusinessDate(r['estimatedStockout']);
  return d == null ? null : 'Estimated stock-out: ${formatShortDate(d)}';
}

/// explainAverage.
String _explain(Map r) {
  final unit = r['unitOfMeasure'];
  final windowDays = _n(r['windowDays'])?.toInt() ?? 0;
  final lookback = _n(r['lookbackDays'])?.toInt() ?? 0;
  if (r['status'] == 'InsufficientHistory') {
    return 'Stocked for only $windowDays day${windowDays == 1 ? '' : 's'} — at least a few days of use are needed for an estimate.';
  }
  if ((_n(r['consumedQty']) ?? 0) <= 0) {
    return 'Nothing used from ${formatShortDate(r['windowFrom'])} to ${formatShortDate(r['windowTo'])}.';
  }
  final over = windowDays < lookback ? '$windowDays days (since it was first stocked)' : 'the last $windowDays days';
  return '${_qty(r['consumedQty'], unit)} used over $over, ${formatShortDate(r['windowFrom'])}–${formatShortDate(r['windowTo'])}: '
      'about ${_qty(r['avgDailyUsage'], unit, 2)} a day.';
}

/// purchaseUnitEquivalent: "≈ 3.2 Bag" when stock is kept in kg but bought in bags.
String? _bags(Map r) {
  final per = _n(r['unitsPerPurchaseUnit']);
  final q = _n(r['currentQuantity']);
  final pu = r['purchaseUnitOfMeasure'];
  if (q == null || per == null || per <= 1) return null;
  if (pu == null || '$pu'.isEmpty || pu == r['unitOfMeasure']) return null;
  return '≈ ${fmtNum(q / per)} $pu';
}

class _DaysOfSupplyScreenState extends State<DaysOfSupplyScreen> {
  /// Null = the farm's saved default.
  int? _lookback;
  List<Map<String, dynamic>>? _rows;
  String? _error;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final res = await widget.session.farmClient.get('/api/Poultry/stock-supply', query: {
        'farmId': widget.company.farmId,
        if (_lookback != null) 'lookbackDays': '$_lookback',
      });
      final rows = [
        for (final r in LookupLoader.rowsIn(res))
          if (r is Map) Map<String, dynamic>.from(r),
      ];
      // sortBySeverity
      rows.sort((a, b) {
        final s = (_n(a['severityRank']) ?? 0).compareTo(_n(b['severityRank']) ?? 0);
        if (s != 0) return s;
        final d = (_n(a['daysOfSupply']) ?? double.maxFinite).compareTo(_n(b['daysOfSupply']) ?? double.maxFinite);
        if (d != 0) return d;
        return '${a['itemName']}'.compareTo('${b['itemName']}');
      });
      if (mounted) setState(() => _rows = rows);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : 'Could not load stock levels.');
    }
  }

  Future<void> _openSettings() async {
    final messenger = ScaffoldMessenger.of(context);
    Map? s;
    try {
      s = await widget.session.farmClient
          .get('/api/Poultry/stock-supply/settings', query: {'farmId': widget.company.farmId}) as Map?;
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not load settings. ${e.message}')));
      return;
    }
    if (!mounted || s == null) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _WarningLevelsDialog(session: widget.session, company: widget.company, settings: s!),
    );
    if (saved == true) {
      messenger.showSnackBar(const SnackBar(content: Text('Stock warning levels saved')));
      setState(() => _lookback = null);
      _load();
    }
  }

  void _restock(Map r) {
    // The normal purchase dialog with the item already chosen, as the web's
    // restockHref — nothing is bought automatically.
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WebPageScreen(
        label: 'Restock ${r['itemName'] ?? ''}',
        href: '/poultry-raw-materials?purchase=1&itemId=${r['poultryRawMaterialItemId']}',
        company: widget.company,
        session: widget.session,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-days-of-supply');
    final rows = _rows;
    final first = rows?.firstOrNull;
    final shown = [for (final r in rows ?? const <Map<String, dynamic>>[]) if (_showAll || r['status'] != 'NoRecentUsage') r];
    final hiddenIdle = (rows?.length ?? 0) - shown.length;
    final anyExpected = (rows ?? const []).any((r) => r['expectedDailyUsage'] != null);
    final urgent = (rows ?? const []).where((r) => _actionable.contains(r['status'])).length;
    final activeLookback = _lookback ?? _n(first?['lookbackDays'])?.toInt();

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Days of Supply')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Text('How long each item lasts at the rate it is actually being used.',
                style: TextStyle(fontSize: 13, color: tokens.mutedForeground)),
            const SizedBox(height: 12),
            Text('Average over', style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
            const SizedBox(height: 4),
            // The web's `flex flex-wrap items-end gap-2`: on a narrow phone the
            // Warning levels button drops under the lookback toggle.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<int>(
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  showSelectedIcon: false,
                  segments: [for (final d in _lookbacks) ButtonSegment(value: d, label: Text('$d days'))],
                  selected: {if (activeLookback != null && _lookbacks.contains(activeLookback)) activeLookback},
                  emptySelectionAllowed: true,
                  onSelectionChanged: (s) {
                    if (s.isEmpty) return;
                    setState(() => _lookback = s.first);
                    _load();
                  },
                ),
                AppButton(
                  label: 'Warning levels',
                  icon: Icons.tune,
                  variant: AppButtonVariant.outline,
                  size: AppButtonSize.sm,
                  onPressed: _openSettings,
                ),
              ],
            ),
            if (first != null) ...[
              const SizedBox(height: 10),
              Text(
                'Usage from ${formatLongDate(first['windowFrom'])} to ${formatLongDate(first['windowTo'])} (complete '
                'days; today is not counted yet). Critical under ${fmtNum(_n(first['criticalDays']))} days, warning '
                'under ${fmtNum(_n(first['warningDays']))} days. Feed and medication given to flocks and ingredients '
                'used in feed production count as usage; purchases, reversals and stock corrections do not. '
                'Stock-out dates are estimates.',
                style: TextStyle(fontSize: 12, color: tokens.mutedForeground),
              ),
            ],
            const SizedBox(height: 12),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  border: Border.all(color: const Color(0xFFFECDD3)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!, style: const TextStyle(fontSize: 13, color: Color(0xFF9F1239))),
              )
            else if (rows == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else ...[
              Row(
                children: [
                  Expanded(
                    child: Text('$urgent need${urgent == 1 ? 's' : ''} attention · ${rows.length} items',
                        style: TextStyle(fontSize: 13, color: tokens.mutedForeground)),
                  ),
                  if (hiddenIdle > 0)
                    TextButton(
                      onPressed: () => setState(() => _showAll = !_showAll),
                      child: Text(_showAll
                          ? 'Hide items with no recent usage'
                          : 'Show $hiddenIdle item${hiddenIdle == 1 ? '' : 's'} with no recent usage'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Nothing has been used recently.', style: TextStyle(color: tokens.mutedForeground)),
                ),
              for (final r in shown) ...[
                _SupplyCard(row: r, showExpected: anyExpected, onRestock: () => _restock(r)),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SupplyCard extends StatelessWidget {
  const _SupplyCard({required this.row, required this.showExpected, required this.onRestock});
  final Map<String, dynamic> row;
  final bool showExpected;
  final VoidCallback onRestock;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final r = row;
    final (label, bg, fg) = _statusStyle('${r['status']}');
    final out = _stockout(r);
    final bags = _bags(r);
    final unit = r['unitOfMeasure'];
    final negative = (_n(r['currentQuantity']) ?? 0) < 0;
    Widget line(String k, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(children: [
            SizedBox(width: 130, child: Text(k, style: TextStyle(fontSize: 12.5, color: tokens.mutedForeground))),
            Expanded(child: Text(v, style: TextStyle(fontSize: 13, color: color))),
          ]),
        );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text('${r['itemName'] ?? ''}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
              child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg)),
            ),
          ]),
          if ('${r['category'] ?? ''}'.isNotEmpty)
            Text('${r['category']}', style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
          const SizedBox(height: 4),
          Text(_explain(r), style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
          const SizedBox(height: 6),
          line('Current stock', _qty(r['currentQuantity'], unit), color: negative ? const Color(0xFFBE123C) : null),
          if (bags != null) line('', bags),
          if (r['belowReorder'] == true) line('', 'At or below reorder level', color: const Color(0xFFB45309)),
          line('Avg daily use', _qty(r['avgDailyUsage'], unit, 2)),
          if (showExpected) line('Expected (feed rate)', _qty(r['expectedDailyUsage'], unit, 2)),
          line('Days remaining', _days(r)),
          if (out != null) line('', out),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: 'Restock',
              size: AppButtonSize.sm,
              variant: _actionable.contains(r['status']) ? AppButtonVariant.primary : AppButtonVariant.outline,
              onPressed: onRestock,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Stock warning levels": when an item is critical or a warning, and how
/// many days of usage to average. PUT `/Poultry/stock-supply/settings`.
class _WarningLevelsDialog extends StatefulWidget {
  const _WarningLevelsDialog({required this.session, required this.company, required this.settings});
  final Session session;
  final Company company;
  final Map settings;

  @override
  State<_WarningLevelsDialog> createState() => _WarningLevelsDialogState();
}

class _WarningLevelsDialogState extends State<_WarningLevelsDialog> {
  late final _critical = TextEditingController(text: fmtNum(_n(widget.settings['criticalDays'])));
  late final _warning = TextEditingController(text: fmtNum(_n(widget.settings['warningDays'])));
  late final _lookback = TextEditingController(text: '${widget.settings['lookbackDays'] ?? 7}');
  late final _minHistory = TextEditingController(text: '${widget.settings['minHistoryDays'] ?? 3}');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_critical, _warning, _lookback, _minHistory]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.session.farmClient.put('/api/Poultry/stock-supply/settings', body: {
        'criticalDays': double.tryParse(_critical.text.replaceAll(',', '')) ?? 0,
        'warningDays': double.tryParse(_warning.text.replaceAll(',', '')) ?? 0,
        'lookbackDays': int.tryParse(_lookback.text) ?? 7,
        'minHistoryDays': int.tryParse(_minHistory.text) ?? 3,
        'farmId': widget.company.farmId,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      // A 400 carries the server's reason (e.g. warning must exceed critical).
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Not saved. ${e.message}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field(String label, TextEditingController c, {bool decimal = false}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            AppNumberInput(controller: c, allowDecimal: decimal),
          ],
        );
    return AlertDialog(
      title: const Text('Stock warning levels'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('When an item counts as critical or needs a warning, and how many days of usage to average.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            field('Critical under (days)', _critical, decimal: true),
            const SizedBox(height: 8),
            field('Warning under (days)', _warning, decimal: true),
            const SizedBox(height: 8),
            field('Default average over (days)', _lookback),
            const SizedBox(height: 8),
            field('Minimum history (days)', _minHistory),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
      ],
    );
  }
}
