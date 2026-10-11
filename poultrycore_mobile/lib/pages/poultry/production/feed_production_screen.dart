// Poultry → Operations → Production → Feed Production
// (app/poultry-feed-production): the batch list (tiles, search + status,
// cards and table, paging, delete), the new-batch page, and the batch page —
// the form while a Draft (or a Reversed batch being edited), otherwise the
// read-only detail with Reverse / Repost / Edit / Delete and traceability.

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../reports/report_format.dart' show FarmMoney;
import '../reports/report_routes.dart' show openAppHref;
import '../sales/balances_widgets.dart' show ListFiltersCard, CompactPager;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, loc;
import '../trackers/tracker_widgets.dart';
import 'feed_production_form.dart';
import 'production_records_screen.dart' show ProdCard;

const feedSourceLabels = {'FromInventory': 'From inventory', 'BoughtDuringProduction': 'Bought during production', 'MixedSource': 'Mixed source'};

const productionCostTooltip =
    'What this batch cost to make: the ingredients at the cost they were drawn at, plus milling, labour and any other production costs. This is what cost per unit is based on.';
const carriedForwardTooltip =
    'The part of that cost still waiting to reach Profit & Loss, carried into the feed this batch made. Ingredients already expensed when they were bought are not in this figure, and neither are milling and labour -- they are expenses of their own already.';
const deferredInventoryTooltip = 'What this stock still owes Profit & Loss. It is charged as you record usage.';
const expensedAtPurchaseTooltip = 'This stock was charged to Profit & Loss when it was bought. Using it reduces the quantity but adds no new expense.';

Widget feedStatusBadge(Object? status) => switch (tStr(status)) {
  'Posted' => const TBadge('Posted', bg: TColors.emerald600, fg: Colors.white),
  'Reversed' => const TBadge('Reversed', bg: Colors.white, fg: TColors.slate500, border: TColors.slate200),
  final s => TBadge(s, bg: TColors.slate100, fg: TColors.slate800),
};

String _qtyUnit(Map b) => '${loc(tNum(b['quantityProduced']))}${tStr(b['outputUnit']).isNotEmpty ? ' ${tStr(b['outputUnit'])}' : ''}';

class FeedProductionScreen extends StatefulWidget {
  const FeedProductionScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<FeedProductionScreen> createState() => _FeedProductionScreenState();
}

class _FeedProductionScreenState extends State<FeedProductionScreen> {
  bool _loading = true, _table = false;
  List<Map> _batches = [];
  final _search = TextEditingController();
  String _status = 'all';
  int _page = 1, _size = 10;
  FarmMoney _gh = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  bool get _canManage => (widget.company.role ?? '').toLowerCase() != 'staff';
  bool get _showCost => (widget.company.role ?? '').toLowerCase() != 'staff';

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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = rowsOf(await _api.get('/api/Poultry/feed-production', query: {'farmId': widget.company.farmId}));
      if (mounted) setState(() => _batches = rows);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to load feed production batches', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map> get _filtered {
    final s = _search.text.trim().toLowerCase();
    return [
      for (final b in _batches)
        if ((s.isEmpty || ['batchNumber', 'finishedFeedItemName', 'formulaName'].any((k) => tStr(b[k]).toLowerCase().contains(s))) &&
            (_status == 'all' || tStr(b['status']) == _status))
          b,
    ];
  }

  Future<void> _open(Map b) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            FeedProductionBatchScreen(session: widget.session, company: widget.company, batchId: tIntOrNull(b['poultryFeedProductionBatchId']) ?? 0),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _new() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FeedProductionNewScreen(session: widget.session, company: widget.company),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _delete(Map b) async {
    final ok = await confirmDelete(context, title: 'Delete batch?', description: 'Batch ${tStr(b['batchNumber'])} will be permanently removed.');
    if (ok != true || !mounted) return;
    try {
      await _api.delete('/api/Poultry/feed-production/${b['poultryFeedProductionBatchId']}?farmId=${Uri.encodeQueryComponent(widget.company.farmId)}');
      if (mounted) trackerToast(context, 'Batch deleted');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to delete', description: e.message, error: true);
    }
  }

  bool _editable(Map b) => (tStr(b['status']) == 'Draft' || tStr(b['status']) == 'Reversed') && _canManage;

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-feed-production');
    final rows = _filtered;
    final pages = rows.isEmpty ? 1 : (rows.length + _size - 1) ~/ _size;
    final page = _page.clamp(1, pages);
    final pageRows = rows.skip((page - 1) * _size).take(_size).toList();
    final posted = [
      for (final b in _batches)
        if (tStr(b['status']) == 'Posted') b,
    ];
    final produced = posted.fold<num>(0, (s, b) => s + tNum(b['totalProductionCost']));
    final drafts = _batches.where((b) => tStr(b['status']) == 'Draft').length;

    Widget stat(IconData icon, Color color, String label, String value) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: .5, color: TColors.slate500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Feed Production')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Text('Feed Production', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const Text(
              'Produce finished feed from ingredients — with full costing, inventory and cash impact.',
              style: TextStyle(fontSize: 14, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => openAppHref(context, widget.session, widget.company, '/poultry-feed-formulas', label: 'Feed Formulas'),
                  icon: const Icon(Icons.science_outlined, size: 16),
                  label: const Text('Feed Formulas'),
                ),
                if (_canManage) FilledButton.icon(onPressed: _new, icon: const Icon(Icons.add, size: 16), label: const Text('New Batch')),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Row(
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Loading…'),
                  ],
                ),
              )
            else ...[
              LayoutBuilder(
                builder: (context, c) {
                  final w = (c.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(width: w, child: stat(Icons.factory_outlined, TColors.blue600, 'Batches', loc(_batches.length))),
                      SizedBox(width: w, child: stat(Icons.factory_outlined, TColors.amber600, 'Drafts', loc(drafts))),
                      if (_showCost) SizedBox(width: w, child: stat(Icons.factory_outlined, TColors.emerald600, 'Produced value (posted)', _gh(produced))),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              TCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListFiltersCard(
                      search: _search,
                      searchPlaceholder: 'Search batch, feed or formula',
                      searchOnly: true,
                      onSearch: () => setState(() => _page = 1),
                      from: '',
                      to: '',
                      onDates: (_, _) {},
                      onClear: () => setState(_search.clear),
                      extras: [
                        AppSelect<String>(
                          value: _status,
                          items: const [
                            AppSelectItem(value: 'all', label: 'All statuses'),
                            AppSelectItem(value: 'Draft', label: 'Draft'),
                            AppSelectItem(value: 'Posted', label: 'Posted'),
                            AppSelectItem(value: 'Reversed', label: 'Reversed'),
                          ],
                          onChanged: (v) => setState(() => _status = v ?? 'all'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!_table)
                      rows.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Text(
                                'No feed production batches yet.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: TColors.slate400),
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < pageRows.length; i++) ...[_card(pageRows[i], i), const SizedBox(height: 12)],
                                ViewTableButton(onPressed: () => setState(() => _table = true)),
                              ],
                            )
                    else ...[
                      TableViewBar(text: 'Table view • Scroll → for more', onCards: () => setState(() => _table = false)),
                      _tableView(pageRows),
                    ],
                    CompactPager(
                      total: rows.length,
                      page: page,
                      pageSize: _size,
                      onPage: (p) => setState(() => _page = p),
                      onPageSize: (s) => setState(() {
                        _size = s;
                        _page = 1;
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card(Map b, int i) {
    Widget tile(String label, String value, Color bg, Color border, Color fg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4, color: fg),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: fg),
          ),
        ],
      ),
    );
    Widget kv(String l, String v) => Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$l ',
            style: const TextStyle(color: TColors.slate500),
          ),
          TextSpan(
            text: v,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 14),
    );
    final editable = _editable(b);
    final produced = tile('Produced', _qtyUnit(b), TColors.emerald100, TColors.emerald300, TColors.emerald800);
    return ProdCard(
      key: ValueKey('fpb-${b['poultryFeedProductionBatchId']}'),
      striped: i.isEven,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      tStr(b['batchNumber']),
                      style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900),
                    ),
                    feedStatusBadge(b['status']),
                  ],
                ),
                Text(
                  '${b['productionDate'] != null ? fmtDateTime(b['productionDate'], b, _offset) : '—'}${tStr(b['finishedFeedItemName']).isNotEmpty ? ' • ${tStr(b['finishedFeedItemName'])}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: TColors.slate500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_showCost)
            Row(
              children: [
                Expanded(child: produced),
                const SizedBox(width: 8),
                Expanded(child: tile('Total cost', _gh(tNum(b['totalProductionCost'])), TColors.violet100, const Color(0xFFC4B5FD), const Color(0xFF4C1D95))),
              ],
            )
          else
            produced,
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_showCost) ...[
            LayoutBuilder(
              builder: (context, c) {
                final w = (c.maxWidth - 8) / 2;
                return Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    SizedBox(width: w, child: kv('Ingredients', _gh(tNum(b['totalIngredientCost'])))),
                    SizedBox(width: w, child: kv('Additional', _gh(tNum(b['totalAdditionalCost'])))),
                    SizedBox(
                      width: c.maxWidth,
                      child: kv('Cost / ${tStr(b['outputUnit']).isNotEmpty ? tStr(b['outputUnit']) : 'unit'}', _gh(tNum(b['costPerOutputUnit']))),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size.fromHeight(40)),
                  onPressed: () => _open(b),
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('Open'),
                ),
              ),
              if (editable) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: TColors.red600,
                      side: const BorderSide(color: TColors.red200),
                      minimumSize: const Size.fromHeight(40),
                    ),
                    onPressed: () => _delete(b),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Delete'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _tableView(List<Map> pageRows) => TrackerTable(
    columns: [
      const TCol('Batch #', width: 120),
      const TCol('Date', width: 150),
      const TCol('Finished Feed', width: 150),
      const TCol('Qty', right: true, width: 100),
      if (_showCost) ...const [
        TCol('Ingredient Cost', right: true, width: 120),
        TCol('Add. Cost', right: true, width: 100),
        TCol('Total Cost', right: true, width: 110),
        TCol('Cost/Unit', right: true, width: 100),
      ],
      const TCol('Status', width: 100),
      const TCol('Actions', right: true, width: 150),
    ],
    emptyText: 'No feed production batches yet.',
    rows: [
      for (final b in pageRows)
        [
          InkWell(onTap: () => _open(b), child: cellText(tStr(b['batchNumber']), bold: true)),
          cellText(b['productionDate'] != null ? fmtDateTime(b['productionDate'], b, _offset) : '—'),
          cellText(tStr(b['finishedFeedItemName']).isNotEmpty ? tStr(b['finishedFeedItemName']) : '—'),
          cellText(_qtyUnit(b)),
          if (_showCost) ...[
            cellText(_gh(tNum(b['totalIngredientCost']))),
            cellText(_gh(tNum(b['totalAdditionalCost']))),
            cellText(_gh(tNum(b['totalProductionCost'])), bold: true),
            cellText(_gh(tNum(b['costPerOutputUnit']))),
          ],
          Align(alignment: Alignment.center, child: feedStatusBadge(b['status'])),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(tooltip: 'Open', icon: const Icon(Icons.visibility_outlined, size: 16), onPressed: () => _open(b)),
              if (_editable(b)) ...[
                IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 16), onPressed: () => _open(b)),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline, size: 16, color: TColors.red600),
                  onPressed: () => _delete(b),
                ),
              ],
            ],
          ),
        ],
    ],
  );
}

/// app/poultry-feed-production/new.
class FeedProductionNewScreen extends StatelessWidget {
  const FeedProductionNewScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF9FAFB),
    appBar: AppBar(title: const Text('New Feed Production Batch')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      children: [
        FeedProductionBatchForm(
          session: session,
          company: company,
          onSaved: (id) => Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => FeedProductionBatchScreen(session: session, company: company, batchId: id),
            ),
          ),
        ),
      ],
    ),
  );
}

/// app/poultry-feed-production/[id].
class FeedProductionBatchScreen extends StatefulWidget {
  const FeedProductionBatchScreen({super.key, required this.session, required this.company, required this.batchId});
  final Session session;
  final Company company;
  final int batchId;
  @override
  State<FeedProductionBatchScreen> createState() => _FeedProductionBatchScreenState();
}

class _FeedProductionBatchScreenState extends State<FeedProductionBatchScreen> {
  bool _loading = true, _editing = false, _reposting = false;
  Map? _batch;
  List<Map> _trace = [];
  FarmMoney _gh = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;
  int _formSeed = 0;

  ApiClient get _api => widget.session.farmClient;
  Map<String, String> get _farm => {'farmId': widget.company.farmId};
  bool get _canManage => (widget.company.role ?? '').toLowerCase() != 'staff';

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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final b = await _api.get('/api/Poultry/feed-production/${widget.batchId}', query: _farm);
      if (mounted && b is Map) {
        setState(() {
          _batch = b;
          _formSeed++;
        });
        _loadTrace();
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to load batch', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadTrace() async {
    try {
      final t = rowsOf(await _api.get('/api/Poultry/feed-production/${widget.batchId}/traceability', query: _farm));
      if (mounted) setState(() => _trace = t);
    } on ApiException {
      if (mounted) setState(() => _trace = []);
    }
  }

  Future<void> _reverse() async {
    final reason = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        var busy = false;
        return StatefulBuilder(
          builder: (ctx, set) => PopScope(
            canPop: !busy,
            child: AlertDialog(
              title: const Text('Reverse this batch?'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'This restores the ingredients consumed from inventory, removes the produced feed from stock, and reverses any cash posted. Blocked if any produced feed has already been used.',
                      style: TextStyle(fontSize: 14, color: TColors.slate600),
                    ),
                    const SizedBox(height: 12),
                    const Text('Reason (optional)', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                    const SizedBox(height: 4),
                    AppInput(controller: reason, hintText: 'Why is this being reversed?'),
                  ],
                ),
              ),
              actions: [
                OutlinedButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: TColors.red600),
                  onPressed: busy
                      ? null
                      : () async {
                          set(() => busy = true);
                          try {
                            await _api.post(
                              '/api/Poultry/feed-production/${widget.batchId}/reverse',
                              body: {
                                'farmId': widget.company.farmId,
                                'userId': widget.session.tokens.userId,
                                'reversalReason': reason.text.isEmpty ? null : reason.text,
                              },
                            );
                            if (mounted) {
                              trackerToast(context, 'Batch reversed', description: 'Ingredient stock restored, produced feed removed, cash reversed.');
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _load();
                          } on ApiException catch (e) {
                            if (mounted) trackerToast(context, 'Failed to reverse batch', description: e.message, error: true);
                            set(() => busy = false);
                          }
                        },
                  icon: const Icon(Icons.undo, size: 16),
                  label: Text(busy ? 'Reversing…' : 'Reverse Batch'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _repost() async {
    setState(() => _reposting = true);
    try {
      final posted = await _api.post(
        '/api/Poultry/feed-production/${widget.batchId}/post',
        body: {'farmId': widget.company.farmId, 'userId': widget.session.tokens.userId},
      );
      if (mounted) {
        trackerToast(context, 'Batch reposted', description: 'Cost/unit ${_gh(posted is Map ? tNum(posted['costPerOutputUnit']) : 0)} · stock & cash updated.');
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to repost batch', description: e.message, error: true);
    }
    if (mounted) setState(() => _reposting = false);
  }

  Future<void> _delete() async {
    final b = _batch!;
    final ok = await confirmDelete(
      context,
      title: 'Delete reversed batch?',
      description: 'Batch ${tStr(b['batchNumber'])} will be permanently removed. This is only allowed because it has already been reversed.',
    );
    if (ok != true || !mounted) return;
    try {
      await _api.delete('/api/Poultry/feed-production/${widget.batchId}?farmId=${Uri.encodeQueryComponent(widget.company.farmId)}');
      if (!mounted) return;
      trackerToast(context, 'Batch deleted');
      Navigator.of(context).maybePop();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to delete batch', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _batch;
    final status = tStr(b?['status']);
    final form = b != null && (status == 'Draft' || (status == 'Reversed' && _editing));
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(title: Text(b == null ? 'Feed Production' : 'Batch ${tStr(b['batchNumber'])}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          if (_loading && b == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Loading…'),
                ],
              ),
            )
          else if (b == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('Batch not found.', style: TextStyle(color: TColors.slate500)),
            )
          else if (form)
            FeedProductionBatchForm(
              key: ValueKey('fp-form-$_formSeed'),
              session: widget.session,
              company: widget.company,
              existing: b,
              onSaved: (_) {
                setState(() => _editing = false);
                _load();
              },
            )
          else
            ..._detail(b),
        ],
      ),
    );
  }

  List<Widget> _detail(Map b) {
    final status = tStr(b['status']);
    Widget line(String label, String value, {bool bold = false, String? hint, String? tone}) {
      final color = tone == 'amber' ? const Color(0xFF92400E) : (tone == 'muted' ? TColors.slate500 : null);
      final row = Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Flexible(
              flex: 3,
              child: Text(
                label,
                style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w600 : null, color: color ?? (bold ? TColors.slate900 : TColors.slate600)),
              ),
            ),
            if (hint != null)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.info_outline, size: 13, color: TColors.slate400),
              ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Text(
                value,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w600 : null, color: color ?? (bold ? TColors.slate900 : null)),
              ),
            ),
          ],
        ),
      );
      return hint == null ? row : Tooltip(message: hint, triggerMode: TooltipTriggerMode.tap, showDuration: const Duration(seconds: 8), child: row);
    }

    Widget card(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: .6, color: TColors.slate500),
            ),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
    String when(Object? v) {
      final d = DateTime.tryParse(tStr(v));
      if (d == null) return '—';
      final l = d.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
      return '${l.month}/${l.day}/${l.year}, $h:${two(l.minute)}:${two(l.second)} ${l.hour < 12 ? 'AM' : 'PM'}';
    }

    final lines = [
      for (final x in (b['lines'] as List? ?? const []))
        if (x is Map) x,
    ];
    final costs = [
      for (final x in (b['additionalCosts'] as List? ?? const []))
        if (x is Map) x,
    ];
    final canManage = _canManage;
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton.icon(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, size: 16), label: const Text('Back')),
          Text('Batch ${tStr(b['batchNumber'])}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          status == 'Posted' ? feedStatusBadge(status) : TBadge(status, bg: Colors.white, fg: TColors.slate700, border: TColors.slate200),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (status == 'Posted' && canManage) OutlinedButton.icon(onPressed: _reverse, icon: const Icon(Icons.undo, size: 16), label: const Text('Reverse')),
          if (status == 'Reversed' && canManage)
            OutlinedButton.icon(
              onPressed: _reposting ? null : _repost,
              icon: const Icon(Icons.restart_alt, size: 16),
              label: Text(_reposting ? 'Reposting…' : 'Repost'),
            ),
          if (status == 'Reversed' && canManage)
            OutlinedButton.icon(onPressed: () => setState(() => _editing = true), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
          if (status == 'Reversed' && canManage)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: TColors.red600),
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Delete'),
            ),
        ],
      ),
      const SizedBox(height: 12),
      card('OUTPUT', [
        line('Finished feed', tStr(b['finishedFeedItemName']).isNotEmpty ? tStr(b['finishedFeedItemName']) : '—'),
        line('Quantity', _qtyUnit(b)),
        line('Formula', tStr(b['formulaName']).isNotEmpty ? tStr(b['formulaName']) : '—'),
        line('Date', b['productionDate'] != null ? fmtDateTime(b['productionDate'], b, _offset) : '—'),
      ]),
      card('COST', [
        line('Ingredient cost', _gh(tNum(b['totalIngredientCost']))),
        line('Additional cost', _gh(tNum(b['totalAdditionalCost']))),
        line('Total production cost', _gh(tNum(b['totalProductionCost'])), bold: true, hint: productionCostTooltip),
        line('Cost per unit', _gh(tNum(b['costPerOutputUnit'])), bold: true),
        if (status == 'Posted' && tStr(b['costRecognitionStatus']).isNotEmpty) ...[
          const Divider(height: 16),
          if (tNum(b['deferredProductionCost']) > 0) ...[
            line('Cost carried forward to feed inventory', _gh(tNum(b['deferredProductionCost'])), tone: 'amber', hint: carriedForwardTooltip),
            line('Still in the feed, unconsumed', _gh(tNum(b['deferredRemainingCost'])), tone: 'amber', hint: deferredInventoryTooltip),
          ] else
            line('Cost carried forward to feed inventory', 'None', tone: 'muted', hint: expensedAtPurchaseTooltip),
          Text(tStr(b['costRecognitionStatus']), style: const TextStyle(fontSize: 11, color: TColors.slate500)),
        ],
      ]),
      card('AUDIT', [
        line('Created by', tStr(b['createdBy']).isNotEmpty ? tStr(b['createdBy']) : '—'),
        line('Posted', b['postedAt'] != null ? when(b['postedAt']) : '—'),
        if (status == 'Reversed') ...[
          line('Reversed', b['reversedAt'] != null ? when(b['reversedAt']) : '—'),
          line('Reason', tStr(b['reversalReason']).isNotEmpty ? tStr(b['reversalReason']) : '—'),
        ],
      ]),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Ingredient breakdown', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TrackerTable(
                columns: const [
                  TCol('Ingredient', width: 140),
                  TCol('Source', width: 170),
                  TCol('Qty', right: true, width: 130),
                  TCol('Unit cost', right: true, width: 100),
                  TCol('Total', right: true, width: 100),
                  TCol('Supplier', width: 110),
                  TCol('Payment', width: 90),
                ],
                rows: [
                  for (final l in lines)
                    [
                      cellText(tStr(l['ingredientName'])),
                      cellText(feedSourceLabels[tStr(l['sourceType'])] ?? tStr(l['sourceType'])),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${loc(tNum(l['quantityUsed']))}${tStr(l['unitOfMeasure']).isNotEmpty ? ' ${tStr(l['unitOfMeasure'])}' : ''}'),
                          if (tStr(l['quantityMode']) == 'FixedQuantity' && tNum(l['fixedQuantity']) > 0)
                            Text('from ${loc(tNum(l['fixedQuantity']))} in the recipe', style: const TextStyle(fontSize: 11, color: TColors.slate400)),
                        ],
                      ),
                      cellText(_gh(tNum(l['unitCost']))),
                      cellText(_gh(tNum(l['totalCost']))),
                      cellText(tStr(l['supplierName']).isNotEmpty ? tStr(l['supplierName']) : '—'),
                      cellText(tStr(l['paymentStatus']).isNotEmpty ? tStr(l['paymentStatus']) : '—'),
                    ],
                ],
              ),
            ],
          ),
        ),
      ),
      if (costs.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Additional production costs', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TrackerTable(
                  columns: const [TCol('Type', width: 140), TCol('Amount', right: true, width: 110), TCol('Payment', width: 100), TCol('Payee', width: 140)],
                  rows: [
                    for (final c in costs)
                      [
                        cellText(tStr(c['costType'])),
                        cellText(_gh(tNum(c['amount']))),
                        cellText(tStr(c['paymentStatus']).isNotEmpty ? tStr(c['paymentStatus']) : '—'),
                        cellText(tStr(c['payeeName']).isNotEmpty ? tStr(c['payeeName']) : '—'),
                      ],
                  ],
                ),
              ],
            ),
          ),
        ),
      if (_trace.isNotEmpty)
        TCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Where this feed was used (traceability)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TrackerTable(
                columns: const [
                  TCol('Used date', width: 150),
                  TCol('Production record', width: 140),
                  TCol('Qty used', right: true, width: 100),
                  TCol('Unit cost', right: true, width: 100),
                ],
                rows: [
                  for (final t in _trace)
                    [
                      cellText(t['usedDate'] != null ? fmtDateTime(t['usedDate'], t, _offset) : '—'),
                      cellText(tNum(t['productionRecordId']) != 0 ? 'Record #${tStr(t['productionRecordId'])}' : '—'),
                      cellText(loc(tNum(t['quantityDrawn']))),
                      cellText(_gh(tNum(t['unitCostAtDraw']))),
                    ],
                ],
              ),
            ],
          ),
        ),
    ];
  }
}

/// `/poultry-feed-production/new` and `/poultry-feed-production/{id}`.
Widget? feedProductionScreenForHref(String href, Session s, Company c) {
  final uri = Uri.tryParse(href);
  if (uri == null) return null;
  if (uri.path == '/poultry-feed-production/new') return FeedProductionNewScreen(session: s, company: c);
  final m = RegExp(r'^/poultry-feed-production/(\d+)$').firstMatch(uri.path);
  if (m != null) return FeedProductionBatchScreen(session: s, company: c, batchId: int.parse(m[1]!));
  return null;
}
