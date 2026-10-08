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
import '../reports/report_format.dart';
import '../reports/report_routes.dart' show openAppHref;
import '../sales/balances_logic.dart' show pageSlice;
import '../sales/balances_widgets.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, SortState, SortDir, toggleSort, sortRows;
import '../trackers/tracker_widgets.dart';
import 'asset_detail_screen.dart';
import 'asset_logic.dart';
import 'asset_widgets.dart';

/// Poultry → Expenses → Capital Investments/Assets, as `app/poultry-assets/page.tsx`:
/// the register of long-term investments, their cost, depreciation and book value.

String _today() => DateTime.now().toUtc().toIso8601String().substring(0, 10);

/// The API calls the register and the investment page share.
class AssetApi {
  AssetApi(this.session, this.company);
  final Session session;
  final Company company;
  ApiClient get _api => session.farmClient;
  String get _q => 'farmId=${Uri.encodeQueryComponent(company.farmId)}';
  Map<String, Object?> get _who => {'farmId': company.farmId, 'createdBy': session.tokens.userId};

  Future<Map?> get(int id) async {
    final r = await _api.get('/api/Poultry/assets/$id', query: {'farmId': company.farmId});
    return r is Map ? r : null;
  }

  Future<void> correctOriginalCost(int id, num newAmount, String? date, String reason) =>
      _api.put('/api/Poultry/assets/$id/original-cost?$_q', body: {'newAmount': newAmount, 'effectiveDate': date, 'reason': reason, ..._who});

  Future<void> reverseCost(int assetId, int costId, String reason) =>
      _api.delete('/api/Poultry/assets/$assetId/costs/$costId?$_q', body: {'farmId': company.farmId, 'reason': reason, 'createdBy': session.tokens.userId});

  Future<void> reverseDepreciation(int entryId, String reason) => _api.post('/api/Poultry/asset-depreciation/$entryId/reverse',
      query: {'farmId': company.farmId}, body: {'farmId': company.farmId, 'reason': reason, 'createdBy': session.tokens.userId});
}

class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  List<Map> _assets = [], _categories = [], _due = [], _cash = [];
  Map? _summary;
  bool _loading = true, _saving = false;
  final _search = TextEditingController();
  String _status = 'all', _category = 'all';
  SortState _sort = (key: 'acquisitionDate', dir: SortDir.desc);
  int _page = 1, _pageSize = 10, _lastTotal = -1;
  final Set<int> _expanded = {};
  final Map<int, Map> _details = {};
  final Set<int> _detailBusy = {};
  final Map<int, String> _detailError = {};
  FarmMoney _gh = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  late final AssetApi _assetsApi = AssetApi(widget.session, widget.company);

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
    final q = {'farmId': _farmId};
    Future<Object?> soft(String path) async {
      try {
        return await _api.get(path, query: q);
      } on ApiException {
        return const [];
      }
    }

    try {
      final r = await Future.wait([
        _api.get('/api/Poultry/assets', query: q),
        _api.get('/api/Poultry/assets/categories', query: q),
        _api.get('/api/Poultry/assets/summary', query: q),
        soft('/api/Poultry/asset-depreciation/due'),
        soft('/api/Poultry/cash-accounts'),
      ]);
      if (!mounted) return;
      setState(() {
        _assets = rowsOf(r[0]);
        _categories = rowsOf(r[1]);
        _summary = r[2] is Map ? r[2] as Map : null;
        _due = rowsOf(r[3]);
        _cash = [for (final a in rowsOf(r[4])) if (a['isActive'] == true) a];
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load capital investments', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadDetail(int id) async {
    setState(() {
      _detailBusy.add(id);
      _detailError.remove(id);
    });
    try {
      final full = await _assetsApi.get(id);
      if (mounted && full != null) setState(() => _details[id] = full);
    } on ApiException catch (e) {
      if (mounted) setState(() => _detailError[id] = e.message);
    }
    if (mounted) setState(() => _detailBusy.remove(id));
  }

  void _toggle(int id) {
    setState(() => _expanded.contains(id) ? _expanded.remove(id) : _expanded.add(id));
    if (!_details.containsKey(id)) _loadDetail(id);
  }

  Future<void> _reloadWithOpenDetails() async {
    await _load();
    await Future.wait([for (final id in _expanded) _loadDetail(id)]);
  }

  int _id(Map a) => tIntOrNull(a['poultryCapitalAssetId']) ?? 0;

  Future<void> _dialog(Widget d) async {
    final done = await showDialog<bool>(context: context, builder: (_) => d);
    if (done == true) await _load();
  }

  Future<void> _edit(Map a) => _dialog(AssetEditDialog(
        session: widget.session,
        company: widget.company,
        asset: a,
        categories: _categories,
        fmt: _gh,
        offset: _offset,
        onCorrectOriginalCost: () => _correct(a),
      ));

  Future<void> _addCost(Map a) => _dialog(AddAssetCostDialog(session: widget.session, company: widget.company, asset: a, cashAccounts: _cash, fmt: _gh));

  Future<void> _correct(Map a) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => CorrectOriginalCostDialog(
        asset: a,
        fmt: _gh,
        onSubmit: (amount, date, reason) => _assetsApi.correctOriginalCost(_id(a), amount, date, reason),
      ),
    );
    if (done == true && mounted) {
      trackerToast(context, 'Original cost corrected',
          description: 'The correction is on the cost history with your reason. Depreciation already posted is unchanged.');
      await _reloadWithOpenDetails();
    }
  }

  Future<void> _reverseCost(int assetId, Map row) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => ReasonTextPrompt(
        title: 'Reverse this capitalised cost',
        description:
            "The entry is kept on the record and marked reversed, and the investment's value falls by ${_gh(tNum(row['amount']))}. Any cash paid is returned and any balance owed is closed. Nothing is charged to profit.",
        placeholder: 'Entered against the wrong investment',
        confirmLabel: 'Reverse cost',
        onSubmit: (reason) => _assetsApi.reverseCost(assetId, tIntOrNull(row['poultryCapitalAssetCostId']) ?? 0, reason),
      ),
    );
    if (done == true && mounted) {
      trackerToast(context, 'Cost reversed', description: 'The entry is kept with its reason.');
      await _reloadWithOpenDetails();
    }
  }

  Future<void> _reverseDep(Map row) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => ReasonTextPrompt(
        title: 'Reverse this depreciation charge',
        description:
            'The original entry is kept and an opposite one is written beside it, so the history still shows what was charged and when. No cash is affected.',
        placeholder: 'Wrong in-service month',
        confirmLabel: 'Reverse charge',
        onSubmit: (reason) => _assetsApi.reverseDepreciation(tIntOrNull(row['poultryAssetDepreciationId']) ?? 0, reason),
      ),
    );
    if (done == true && mounted) {
      trackerToast(context, 'Depreciation reversed', description: 'The original entry is kept and an opposite entry added. No cash moved.');
      await _reloadWithOpenDetails();
    }
  }

  Future<void> _viewCost(Map asset, Map row) async {
    final locked = tNum(asset['depreciationEntries']) > 0;
    final reverse = await showDialog<bool>(
      context: context,
      builder: (ctx) => CostDetailDialog(
        cost: row,
        assetName: tStr(asset['assetName']),
        fmt: _gh,
        offset: _offset,
        reverseDisabledReason: locked ? costLockedByDepreciationNote : null,
        onReverse: () => Navigator.pop(ctx, true),
        onOpenExpenses: _openExpenses,
      ),
    );
    if (reverse == true) await _reverseCost(_id(asset), row);
  }

  void _openExpenses() => openAppHref(context, widget.session, widget.company, '/expenses', label: 'Expenses');

  Future<void> _openPage(Map a) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AssetDetailScreen(session: widget.session, company: widget.company, assetId: _id(a)),
    ));
    _load();
  }

  Future<void> _runDepreciation() async {
    setState(() => _saving = true);
    try {
      final res = await _api.post('/api/Poultry/asset-depreciation/generate',
          query: {'farmId': _farmId}, body: {'farmId': _farmId, 'createdBy': widget.session.tokens.userId});
      final created = tIntOrNull(res is Map ? res['entriesCreated'] : null) ?? 0;
      if (mounted) {
        trackerToast(context, created > 0 ? 'Depreciation posted' : 'Nothing was due',
            description: created > 0
                ? '$created month(s) across ${tStr((res as Map)['assetsProcessed'])} asset(s), ${_gh(tNum(res['totalAmount']))} charged to Profit & Loss. No cash moved.'
                : 'Every capital investment is up to date.');
        Navigator.of(context).pop();
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not generate depreciation', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _depreciationDialog() async {
    final dueTotal = _due.fold<num>(0, (s, d) => s + tNum(d['amountDue']));
    final dueMonths = _due.fold<num>(0, (s, d) => s + tNum(d['monthsDue']));
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        return AlertDialog(
          scrollable: true,
          title: const Text('Depreciation'),
          content: SizedBox(
            width: 560,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text(depreciationNoncashNote, style: TextStyle(fontSize: 13, color: TColors.slate500)),
              const SizedBox(height: 12),
              if (_due.isEmpty)
                const Text('Every capital investment is up to date. Nothing is due.', style: TextStyle(fontSize: 13, color: TColors.slate600))
              else ...[
                TrackerTable(
                  columns: const [TCol('Investment', width: 150), TCol('From', width: 110), TCol('Months', right: true, width: 80), TCol('Amount', right: true, width: 120)],
                  rows: [
                    for (final d in _due)
                      [
                        cellText(tStr(d['assetName'])),
                        cellText(fmtDateTime(d['nextPeriod'], null, _offset)),
                        Align(alignment: Alignment.centerRight, child: Text(tStr(d['monthsDue']))),
                        Align(alignment: Alignment.centerRight, child: Text(_gh(tNum(d['amountDue'])))),
                      ],
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: const Color(0xFFFDE68A)), borderRadius: BorderRadius.circular(6)),
                  child: Row(children: [
                    Expanded(
                      child: Text('${dueMonths.toInt()} month(s) across ${_due.length} asset(s) will be charged to Profit & Loss.',
                          style: const TextStyle(fontSize: 13, color: TColors.amber900)),
                    ),
                    Text(_gh(dueTotal), style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.amber900)),
                  ]),
                ),
                const SizedBox(height: 6),
                const Text(depreciationConventionNote, style: TextStyle(fontSize: 11, color: TColors.slate500)),
              ],
            ]),
          ),
          actions: _due.isEmpty
              ? null
              : [
                  OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                  FilledButton(onPressed: _saving ? null : _runDepreciation, child: const Text('Post depreciation')),
                ],
        );
      }),
    );
  }

  Widget _statCard(String label, String value, {String? hint, Color? tone, bool strong = false}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
              color: strong
                  ? TColors.slate300
                  : tone == TColors.amber800
                      ? const Color(0xFFFDE68A)
                      : tone == TColors.emerald800
                          ? const Color(0xFFA7F3D0)
                          : TColors.slate200,
              width: strong ? 1.5 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: .4, color: TColors.slate500)),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: tone)),
          if (hint != null) Text(hint, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
        ]),
      );

  List<Widget> _actions(Map a, {bool compact = false}) {
    if (tStr(a['status']) == 'Reversed') return const [];
    final disposed = tStr(a['status']) == 'Disposed';
    final locked = tNum(a['depreciationEntries']) > 0;
    final open = _expanded.contains(_id(a));
    return [
      if (!compact)
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _toggle(_id(a)),
            icon: Icon(open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 18),
            label: Text(open ? 'Hide history' : 'Where these figures came from'),
          ),
        ),
      OutlinedButton.icon(onPressed: () => _edit(a), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
      if (!disposed)
        Tooltip(
          message: locked ? costLockedByDepreciationNote : 'Add capitalised cost',
          child: OutlinedButton.icon(
              onPressed: locked ? null : () => _addCost(a), icon: const Icon(Icons.payments_outlined, size: 16), label: const Text('Add cost')),
        ),
      if (!disposed && tNum(a['acquisitionCost']) > 0)
        OutlinedButton.icon(onPressed: () => _correct(a), icon: const Icon(Icons.tune, size: 16), label: const Text('Correct cost')),
      if (!disposed)
        OutlinedButton.icon(
          onPressed: () => _dialog(DisposeAssetDialog(session: widget.session, company: widget.company, asset: a, cashAccounts: _cash, fmt: _gh)),
          style: OutlinedButton.styleFrom(foregroundColor: TColors.amber700),
          icon: const Icon(Icons.remove_circle_outline, size: 16),
          label: const Text('Dispose'),
        ),
      if (!locked && !disposed)
        OutlinedButton.icon(
          onPressed: () => _dialog(ReverseAssetDialog(session: widget.session, company: widget.company, asset: a)),
          style: OutlinedButton.styleFrom(foregroundColor: TColors.red600),
          icon: const Icon(Icons.undo, size: 16),
          label: const Text('Reverse'),
        ),
    ];
  }

  Widget _panel(Map a) {
    final id = _id(a);
    return Container(
      decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
      child: AssetDetailsPanel(
        view: _details[id],
        loading: _detailBusy.contains(id),
        error: _detailError[id],
        fmt: _gh,
        offset: _offset,
        onRetry: () => _loadDetail(id),
        onEdit: () => _edit(a),
        onAddCost: () => _addCost(a),
        onCorrectOriginalCost: () => _correct(a),
        onOpenFullPage: () => _openPage(a),
        onOpenExpenses: _openExpenses,
        onViewCost: (row) => _viewCost(a, row),
        onReverseCost: (row) => _reverseCost(id, row),
        onReverseDepreciation: _reverseDep,
      ),
    );
  }

  Widget _table(List<Map> items, int total) {
    void onSort(String k) => setState(() => _sort = toggleSort(k, _sort));
    final open = [for (final a in items) if (_expanded.contains(_id(a))) a];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TrackerTable(
        sort: _sort,
        onSort: onSort,
        emptyText: total == 0
            ? 'No capital investments recorded. A poultry house, a vehicle or a feed mixer belongs here rather than on the Expenses page.'
            : null,
        columns: const [
          TCol('', width: 36),
          TCol('Investment #', sortKey: 'assetNumber', width: 120),
          TCol('Investment', sortKey: 'assetName', width: 150),
          TCol('Category', sortKey: 'categoryName', width: 120),
          TCol('Acquired', sortKey: 'acquisitionDate', width: 140),
          TCol('Capitalised cost', sortKey: 'totalCapitalizedCost', right: true, width: 160),
          TCol('Depreciation', sortKey: 'accumulatedDepreciation', right: true, width: 120),
          TCol('Book value', sortKey: 'currentBookValue', right: true, width: 120),
          TCol('Useful life', sortKey: 'usefulLifeMonths', width: 120),
          TCol('Status', sortKey: 'status', width: 130),
          TCol('Actions', right: true, width: 230),
        ],
        rows: [
          for (final a in items)
            () {
              final id = _id(a);
              final disposed = tStr(a['status']) == 'Disposed';
              final locked = tNum(a['depreciationEntries']) > 0;
              return <Widget>[
                IconButton(
                  tooltip: _expanded.contains(id) ? 'Hide the history' : 'Show where these figures came from',
                  onPressed: () => _toggle(id),
                  icon: Icon(_expanded.contains(id) ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 18, color: TColors.slate400),
                ),
                Text(tStr(a['assetNumber']), style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                InkWell(
                  onTap: () => _openPage(a),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(tStr(a['assetName']), style: const TextStyle(fontWeight: FontWeight.w500)),
                    if (tStr(a['location']).isNotEmpty) Text(tStr(a['location']), style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                  ]),
                ),
                cellText(tStr(a['categoryName']).isEmpty ? '—' : tStr(a['categoryName'])),
                cellText(fmtDateTime(a['acquisitionDate'], a, _offset)),
                Tooltip(
                  message: totalCapitalizedCostTooltip,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                    Text(_gh(tNum(a['totalCapitalizedCost']))),
                    if (tNum(a['additionalCost']) > 0)
                      Text('${_gh(tNum(a['acquisitionCost']))} + ${_gh(tNum(a['additionalCost']))} added',
                          style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                  ]),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(tNum(a['accumulatedDepreciation']) > 0 ? _gh(tNum(a['accumulatedDepreciation'])) : '—',
                      style: const TextStyle(color: TColors.amber700)),
                ),
                Align(alignment: Alignment.centerRight, child: Text(_gh(tNum(a['currentBookValue'])), style: const TextStyle(fontWeight: FontWeight.w500))),
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  tNum(a['usefulLifeMonths']) > 0
                      ? Text('${tStr(a['usefulLifeMonths'])} months')
                      : const Text('Not set', style: TextStyle(color: TColors.slate400)),
                  if (tNum(a['monthlyDepreciation']) > 0)
                    Text('${_gh(tNum(a['monthlyDepreciation']))}/month', style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                ]),
                Align(alignment: Alignment.centerLeft, child: assetStatusBadge(a['status'])),
                tStr(a['status']) == 'Reversed'
                    ? const SizedBox.shrink()
                    : Wrap(alignment: WrapAlignment.end, children: [
                        IconButton(tooltip: 'Edit', onPressed: () => _edit(a), icon: const Icon(Icons.edit_outlined, size: 18)),
                        if (!disposed)
                          IconButton(
                            tooltip: locked ? costLockedByDepreciationNote : 'Add capitalised cost',
                            onPressed: locked ? null : () => _addCost(a),
                            icon: const Icon(Icons.payments_outlined, size: 18),
                          ),
                        if (!disposed && tNum(a['acquisitionCost']) > 0)
                          IconButton(tooltip: 'Correct the original acquisition cost', onPressed: () => _correct(a), icon: const Icon(Icons.tune, size: 18)),
                        if (!disposed)
                          IconButton(
                            tooltip: 'Dispose',
                            onPressed: () =>
                                _dialog(DisposeAssetDialog(session: widget.session, company: widget.company, asset: a, cashAccounts: _cash, fmt: _gh)),
                            icon: const Icon(Icons.remove_circle_outline, size: 18, color: TColors.amber600),
                          ),
                        if (!locked && !disposed)
                          IconButton(
                            tooltip: 'Reverse this acquisition',
                            onPressed: () => _dialog(ReverseAssetDialog(session: widget.session, company: widget.company, asset: a)),
                            icon: const Icon(Icons.undo, size: 18, color: Color(0xFFEF4444)),
                          ),
                      ]),
              ];
            }(),
        ],
      ),
      for (final a in open) ...[const SizedBox(height: 10), Text(tStr(a['assetName']), style: const TextStyle(fontWeight: FontWeight.w600)), _panel(a)],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-assets');
    final filtered = filterAssets(_assets, search: _search.text, status: _status, category: _category);
    final sorted = sortRows(filtered, _sort, (Map a, String k) {
      if (k == 'acquisitionDate') return '${tStr(a['acquisitionDate']).split('T').first}|${tStr(a['createdAt'])}';
      return a[k];
    });
    if (sorted.length != _lastTotal) {
      _lastTotal = sorted.length;
      _page = 1;
    }
    final pageRows = pageSlice(sorted, _page, _pageSize);
    final dueMonths = _due.fold<num>(0, (s, d) => s + tNum(d['monthsDue']));
    final s = _summary;

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Capital Investments/Assets')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Text('Capital Investments/Assets', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: TColors.slate900)),
            const Text('Track major long-term business investments, their cost, depreciation, and current book value.',
                style: TextStyle(fontSize: 12, color: TColors.slate500)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _loading ? null : _depreciationDialog,
                icon: const Icon(Icons.event_repeat, size: 16),
                label: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Depreciation'),
                  if (dueMonths > 0) ...[const SizedBox(width: 8), TBadge('${dueMonths.toInt()} due', bg: TColors.amber100, fg: TColors.amber800)],
                ]),
              ),
              FilledButton.icon(
                onPressed: () => _dialog(NewAssetDialog(session: widget.session, company: widget.company, categories: _categories, cashAccounts: _cash, fmt: _gh)),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New investment'),
              ),
            ]),
            if (s != null) ...[
              const SizedBox(height: 12),
              twoUp([
                _statCard('Total capitalised cost', _gh(tNum(s['totalAssetCost'])), hint: totalCapitalizedCostTooltip),
                _statCard('Depreciation so far', _gh(tNum(s['accumulatedDepreciation'])),
                    hint: 'Charged to Profit & Loss over time. No cash moved.', tone: TColors.amber800),
                _statCard('Current book value', _gh(tNum(s['currentBookValue'])), hint: bookValueTooltip, tone: TColors.emerald800, strong: true),
                _statCard('Added this period', _gh(tNum(s['addedInPeriod'])), hint: '${tStr(s['addedCount']).isEmpty ? '0' : tStr(s['addedCount'])} asset(s) acquired'),
                _statCard('Active investments', tStr(s['activeAssets']).isEmpty ? '0' : tStr(s['activeAssets']),
                    hint: '${tStr(s['draftAssets']).isEmpty ? '0' : tStr(s['draftAssets'])} not in service · ${tStr(s['fullyDepreciated']).isEmpty ? '0' : tStr(s['fullyDepreciated'])} fully depreciated'),
              ]),
            ],
            const SizedBox(height: 12),
            ListFiltersCard(
              search: _search,
              searchPlaceholder: 'Search investment, number, location or supplier',
              searchOnly: true,
              onSearch: () => setState(() {}),
              from: '',
              to: '',
              onDates: (_, _) {},
              onClear: () => setState(_search.clear),
              extras: [
                AppSelect<String>(
                  value: _status,
                  items: [
                    const AppSelectItem(value: 'all', label: 'All statuses'),
                    for (final st in assetStatuses) AppSelectItem(value: st, label: assetStatusLabel(st)),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? 'all'),
                ),
                AppSelect<String>(
                  value: _category,
                  items: [
                    const AppSelectItem(value: 'all', label: 'All categories'),
                    for (final c in _categories) AppSelectItem(value: tStr(c['poultryAssetCategoryId']), label: tStr(c['categoryName'])),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? 'all'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (sorted.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                child: const Text(
                  'No capital investments recorded. A poultry house, a vehicle or a feed mixer belongs here rather than on the Expenses page.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: TColors.slate500),
                ),
              )
            else
              MobileCardList<Map>(
                striped: true,
                items: pageRows,
                keyOf: (a) => tStr(a['poultryCapitalAssetId']),
                primary: (a) => tStr(a['assetName']),
                secondary: (a) =>
                    '${tStr(a['assetNumber'])} · ${tStr(a['categoryName']).isEmpty ? 'Uncategorised' : tStr(a['categoryName'])}${tStr(a['location']).isNotEmpty ? ' · ${tStr(a['location'])}' : ''}',
                trailing: (a) => Padding(padding: const EdgeInsets.only(left: 6), child: assetStatusBadge(a['status'])),
                highlights: (a) => [
                  Highlight('Book value', _gh(tNum(a['currentBookValue'])), accent: Accent.emerald, wide: true),
                  Highlight('Capitalised cost', _gh(tNum(a['totalCapitalizedCost'])), accent: Accent.blue),
                  Highlight('Depreciation', tNum(a['accumulatedDepreciation']) > 0 ? _gh(tNum(a['accumulatedDepreciation'])) : '—', accent: Accent.amber),
                ],
                details: (a) => [
                  ('Acquired', fmtDateTime(a['acquisitionDate'], a, _offset).isEmpty ? '—' : fmtDateTime(a['acquisitionDate'], a, _offset)),
                  ('Original acquisition', _gh(tNum(a['acquisitionCost']))),
                  ('Added since', tNum(a['additionalCost']) > 0 ? _gh(tNum(a['additionalCost'])) : '—'),
                  (
                    'Useful life',
                    tNum(a['usefulLifeMonths']) > 0
                        ? '${tStr(a['usefulLifeMonths'])} months${tNum(a['monthlyDepreciation']) != 0 ? ' · ${_gh(tNum(a['monthlyDepreciation']))}/month' : ''}'
                        : 'Not set'
                  ),
                ],
                actions: _actions,
                extra: (a) => _expanded.contains(_id(a)) ? _panel(a) : const SizedBox.shrink(),
                table: (items) => _table(items, sorted.length),
                pager: CompactPager(
                  total: sorted.length,
                  page: _page,
                  pageSize: _pageSize,
                  onPage: (p) => setState(() => _page = p),
                  onPageSize: (v) => setState(() {
                    _pageSize = v;
                    _page = 1;
                  }),
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'Capital investments affect Cash Flow when they are paid for and appear on Supplier Balances when they are bought on credit. They are not charged against profit in the month they are bought — their cost reaches Profit & Loss over time through depreciation.',
              style: TextStyle(fontSize: 11, color: TColors.slate500),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ dialogs

Widget _num(TextEditingController c, VoidCallback changed, {bool enabled = true}) => AppInput(
      controller: c,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
      onChanged: (_) => changed(),
    );

Widget _hinted(String label, Widget field, String? hint) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FilterLabel(label, field),
      if (hint != null)
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(hint, style: const TextStyle(fontSize: 11, color: TColors.slate500))),
    ]);

Widget _readOnly(String value, {bool bold = false}) => Container(
      height: 44,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
      child: Text(value, style: TextStyle(color: TColors.slate500, fontWeight: bold ? FontWeight.w600 : null)),
    );

Widget _dateField(String value, ValueChanged<String> on, {bool enabled = true, bool clearable = false}) => AppDateField(
      enabled: enabled,
      value: value.isEmpty ? null : businessDateAsDateTime(value),
      hintText: 'dd/mm/yyyy',
      onChanged: (d) => on(d == null ? (clearable ? '' : value) : isoDay(d)),
    );

AppSelect<String> _accountSelect(List<Map> accounts, String value, ValueChanged<String> on) => AppSelect<String>(
      value: value.isEmpty ? null : value,
      hintText: 'Cash account',
      items: [for (final a in accounts) AppSelectItem(value: tStr(a['poultryCashAccountId']), label: tStr(a['accountName']))],
      onChanged: (v) => on(v ?? ''),
    );

const _blue = Color(0xFF2563EB);

/// New capital investment.
class NewAssetDialog extends StatefulWidget {
  const NewAssetDialog({super.key, required this.session, required this.company, required this.categories, required this.cashAccounts, required this.fmt});
  final Session session;
  final Company company;
  final List<Map> categories, cashAccounts;
  final FarmMoney fmt;

  @override
  State<NewAssetDialog> createState() => _NewAssetDialogState();
}

class _NewAssetDialogState extends State<NewAssetDialog> {
  final _name = TextEditingController(), _location = TextEditingController(), _serial = TextEditingController();
  final _desc = TextEditingController(), _amount = TextEditingController(), _supplier = TextEditingController();
  final _paid = TextEditingController(), _life = TextEditingController(), _residual = TextEditingController(text: '0');
  String _category = '', _account = '', _acquired = _today(), _due = '', _inService = '';
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _location, _serial, _desc, _amount, _supplier, _paid, _life, _residual]) {
      c.dispose();
    }
    super.dispose();
  }

  Map? get _cat => widget.categories.where((c) => tStr(c['poultryAssetCategoryId']) == _category).firstOrNull;

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return trackerToast(context, 'Name the investment', error: true);
    setState(() => _saving = true);
    final p = newAssetPreview(_amount.text, _paid.text, _life.text, _residual.text);
    final life = num.tryParse(_life.text) ?? 0;
    String? opt(TextEditingController c) => c.text.isEmpty ? null : c.text;
    try {
      await widget.session.farmClient.post('/api/Poultry/assets', query: {'farmId': widget.company.farmId}, body: {
        'assetName': _name.text,
        'assetCategoryId': _category.isEmpty ? null : int.parse(_category),
        'description': opt(_desc),
        'acquisitionDate': _acquired.isEmpty ? null : _acquired,
        'inServiceDate': _inService.isEmpty ? null : _inService,
        'amount': p.amount > 0 ? p.amount : null,
        'residualValue': num.tryParse(_residual.text) ?? 0,
        'usefulLifeMonths': life > 0 ? life : null,
        'supplier': opt(_supplier),
        'supplierId': null,
        'paymentMethod': 'Cash',
        'amountPaid': p.amount > 0 ? p.paid : null,
        'dueDate': _due.isEmpty ? null : _due,
        'cashAccountId': _account.isEmpty ? null : int.parse(_account),
        'location': opt(_location),
        'serialNumber': opt(_serial),
        'notes': null,
        'farmId': widget.company.farmId,
        'createdBy': widget.session.tokens.userId,
      });
      if (!mounted) return;
      trackerToast(context, 'Investment recorded', description: "It is in the register and excluded from this period's operating expenses.");
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not record the investment', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = widget.fmt;
    final p = newAssetPreview(_amount.text, _paid.text, _life.text, _residual.text);
    final cat = _cat;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const Text('New capital investment'),
        content: SizedBox(
          width: 620,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              'A major long-term purchase. Cash and supplier balances behave exactly as they do for a bill; the cost is recognised over time through depreciation rather than charged to this period.',
              style: TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            formSection('What it is', _blue, [
              FilterLabel('Investment name', AppInput(controller: _name, hintText: 'Poultry House 4')),
              FilterLabel(
                'Category',
                AppSelect<String>(
                  value: _category.isEmpty ? null : _category,
                  hintText: 'Choose a category',
                  items: [for (final c in widget.categories) AppSelectItem(value: tStr(c['poultryAssetCategoryId']), label: tStr(c['categoryName']))],
                  onChanged: (v) => setState(() {
                    _category = v ?? '';
                    // The category's usual life fills an empty field only.
                    if (_life.text.isEmpty) _life.text = tStr(_cat?['defaultUsefulLifeMonths']);
                  }),
                ),
              ),
              FilterLabel('Location', AppInput(controller: _location)),
              FilterLabel('Serial number', AppInput(controller: _serial)),
              FilterLabel('Description', AppInput(controller: _desc, minLines: 2, maxLines: 4)),
            ]),
            const SizedBox(height: 12),
            formSection('What it cost', _blue, [
              FilterLabel('Acquisition date', _dateField(_acquired, (v) => setState(() => _acquired = v), clearable: true)),
              _hinted('Cost', _num(_amount, () => setState(() {})), 'Leave blank for an investment you will build up cost by cost.'),
              FilterLabel('Supplier / payee', AppInput(controller: _supplier)),
              _hinted('Amount paid now', _num(_paid, () => setState(() {})), 'Leave blank if paid in full.'),
              FilterLabel('Paid from', _accountSelect(widget.cashAccounts, _account, (v) => setState(() => _account = v))),
              FilterLabel('Balance due date', _dateField(_due, (v) => setState(() => _due = v), clearable: true)),
            ]),
            const SizedBox(height: 12),
            formSection('How it depreciates', _blue, [
              _hinted('In-service date', _dateField(_inService, (v) => setState(() => _inService = v), clearable: true),
                  'Depreciation starts in this month. Leave blank if it is not in use yet.'),
              _hinted('Useful life (months)', _num(_life, () => setState(() {})),
                  tNum(cat?['defaultUsefulLifeMonths']) > 0 ? '${tStr(cat!['categoryName'])} usually ${tStr(cat['defaultUsefulLifeMonths'])} months' : null),
              _hinted('Residual value', _num(_residual, () => setState(() {})),
                  'What you expect it to still be worth at the end. Book value never falls below it.'),
              FilterLabel('Method', _readOnly('Straight line')),
            ]),
            if (p.amount > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFF0F9FF), border: Border.all(color: const Color(0xFFBAE6FD)), borderRadius: BorderRadius.circular(6)),
                child: DefaultTextStyle(
                  style: const TextStyle(fontSize: 12, color: Color(0xFF0C4A6E)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('What this will record', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text.rich(TextSpan(children: [
                      const TextSpan(text: 'Investment value '),
                      TextSpan(text: fmt(p.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ])),
                    Text.rich(TextSpan(children: [
                      const TextSpan(text: 'Cash out now '),
                      TextSpan(text: fmt(p.paid), style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (p.owing > 0) ...[
                        const TextSpan(text: ' · owed to the supplier '),
                        TextSpan(text: fmt(p.owing), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ])),
                    Text.rich(TextSpan(children: [
                      const TextSpan(text: "Charged against this period's profit "),
                      TextSpan(text: fmt(0), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ])),
                    if (p.monthly > 0)
                      Text.rich(TextSpan(children: [
                        const TextSpan(text: 'Depreciation '),
                        TextSpan(text: fmt(p.monthly), style: const TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: ' a month for ${_life.text} months'),
                      ])),
                    if (_inService.isEmpty)
                      const Text('No in-service date — it will be saved as not in service and will not depreciate yet.',
                          style: TextStyle(color: TColors.amber800)),
                  ]),
                ),
              ),
            ],
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Record investment')),
        ],
      ),
    );
  }
}

/// Edit: names and places always; the depreciation terms only until depreciation is posted.
class AssetEditDialog extends StatefulWidget {
  const AssetEditDialog({
    super.key,
    required this.session,
    required this.company,
    required this.asset,
    required this.categories,
    required this.fmt,
    required this.offset,
    required this.onCorrectOriginalCost,
  });
  final Session session;
  final Company company;
  final Map asset;
  final List<Map> categories;
  final FarmMoney fmt;
  final Duration offset;
  final VoidCallback onCorrectOriginalCost;

  @override
  State<AssetEditDialog> createState() => _AssetEditDialogState();
}

class _AssetEditDialogState extends State<AssetEditDialog> {
  late final Map a = widget.asset;
  late final _name = TextEditingController(text: tStr(a['assetName']));
  late final _location = TextEditingController(text: tStr(a['location']));
  late final _serial = TextEditingController(text: tStr(a['serialNumber']));
  late final _desc = TextEditingController(text: tStr(a['description']));
  late final _notes = TextEditingController(text: tStr(a['notes']));
  late final _life = TextEditingController(text: tStr(a['usefulLifeMonths']));
  late final _residual = TextEditingController(text: tStr(a['residualValue']));
  late String _category = tStr(a['poultryAssetCategoryId']);
  late String _inService = tStr(a['inServiceDate']).split('T').first;
  bool _saving = false;

  bool get _locked => tNum(a['depreciationEntries']) > 0;

  @override
  void dispose() {
    for (final c in [_name, _location, _serial, _desc, _notes, _life, _residual]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final fin = !_locked;
    setState(() => _saving = true);
    String? opt(TextEditingController c) => c.text.isEmpty ? null : c.text;
    try {
      await widget.session.farmClient.put(
        '/api/Poultry/assets/${tStr(a['poultryCapitalAssetId'])}?farmId=${Uri.encodeQueryComponent(widget.company.farmId)}',
        body: {
          'assetName': _name.text,
          'assetCategoryId': _category.isEmpty ? null : int.tryParse(_category),
          'description': opt(_desc),
          'location': opt(_location),
          'serialNumber': opt(_serial),
          'notes': opt(_notes),
          'inServiceDate': fin ? (_inService.isEmpty ? null : _inService) : null,
          'usefulLifeMonths': fin ? (num.tryParse(_life.text) == 0 ? null : num.tryParse(_life.text)) : null,
          'residualValue': fin ? (num.tryParse(_residual.text) ?? 0) : null,
          'setFinancials': fin,
          'farmId': widget.company.farmId,
          'updatedBy': widget.session.tokens.userId,
        },
      );
      if (!mounted) return;
      trackerToast(context, 'Investment updated');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not update the investment', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = widget.fmt;
    final noAcq = tNum(a['acquisitionCost']) <= 0;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Text('Edit ${tStr(a['assetName'])}'),
        content: SizedBox(
          width: 580,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            formSection('Details', _blue, [
              FilterLabel('Investment name', AppInput(controller: _name)),
              FilterLabel(
                'Category',
                AppSelect<String>(
                  value: _category.isEmpty ? null : _category,
                  hintText: 'Choose a category',
                  items: [for (final c in widget.categories) AppSelectItem(value: tStr(c['poultryAssetCategoryId']), label: tStr(c['categoryName']))],
                  onChanged: (v) => setState(() => _category = v ?? ''),
                ),
              ),
              FilterLabel('Location', AppInput(controller: _location)),
              FilterLabel('Serial number', AppInput(controller: _serial)),
              _hinted('Acquired', _readOnly(fmtDateTime(a['acquisitionDate'], a, widget.offset)), 'Set when the investment was recorded and not editable here.'),
              FilterLabel('Investment number', _readOnly(tStr(a['assetNumber']))),
              FilterLabel('Description', AppInput(controller: _desc, minLines: 2, maxLines: 4)),
              FilterLabel('Notes', AppInput(controller: _notes, minLines: 2, maxLines: 4)),
            ]),
            const SizedBox(height: 12),
            formSection('Depreciation', _blue, [
              FilterLabel('In-service date', _dateField(_inService, (v) => setState(() => _inService = v), enabled: !_locked, clearable: true)),
              FilterLabel('Useful life (months)', _num(_life, () => setState(() {}), enabled: !_locked)),
              FilterLabel('Residual value', _num(_residual, () => setState(() {}), enabled: !_locked)),
              FilterLabel('Method', _readOnly('Straight line')),
            ]),
            const SizedBox(height: 12),
            formSection('Cost summary', _blue, [
              _hinted(acquisitionCostLabel, _readOnly(fmt(tNum(a['acquisitionCost']))), acquisitionCostTooltip),
              _hinted(additionalCostLabel, _readOnly(fmt(tNum(a['additionalCost']))), additionalCostTooltip),
              _hinted(totalCapitalizedCostLabel, _readOnly(fmt(tNum(a['totalCapitalizedCost'])), bold: true), totalCapitalizedCostTooltip),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Spent more on it? Use '),
                    TextSpan(text: 'Add cost', style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: '. Typed the wrong amount in the first place? Correct it — the correction is kept on the record with its reason.'),
                  ]),
                  style: TextStyle(fontSize: 11, color: TColors.slate600),
                ),
                const SizedBox(height: 6),
                Tooltip(
                  message: noAcq ? 'This investment has no original acquisition to correct — its cost was built up with Add cost.' : '',
                  child: OutlinedButton.icon(
                    onPressed: noAcq
                        ? null
                        : () {
                            Navigator.pop(context, false);
                            widget.onCorrectOriginalCost();
                          },
                    icon: const Icon(Icons.tune, size: 15),
                    label: const Text('Correct original cost'),
                  ),
                ),
              ]),
            ),
            if (_locked) ...[
              const SizedBox(height: 10),
              amberNote(
                  'Depreciation has been posted for this investment, so its in-service date, useful life and residual value are locked — changing them would make every month already charged wrong. Reverse the depreciation first. The name, category and location can still be edited.'),
            ],
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
        ],
      ),
    );
  }
}

/// Add cost: capitalise real extra money, or be sent to Expenses for an operating cost.
class AddAssetCostDialog extends StatefulWidget {
  const AddAssetCostDialog({super.key, required this.session, required this.company, required this.asset, required this.cashAccounts, required this.fmt});
  final Session session;
  final Company company;
  final Map asset;
  final List<Map> cashAccounts;
  final FarmMoney fmt;

  @override
  State<AddAssetCostDialog> createState() => _AddAssetCostDialogState();
}

class _AddAssetCostDialogState extends State<AddAssetCostDialog> {
  String _treatment = 'capitalise', _method = 'Cash', _account = '', _date = _today(), _due = '';
  final _amount = TextEditingController(), _desc = TextEditingController(), _type = TextEditingController();
  final _supplier = TextEditingController(), _paid = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_amount, _desc, _type, _supplier, _paid]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final amount = num.tryParse(_amount.text) ?? 0;
    if (amount <= 0) return trackerToast(context, 'Enter an amount', error: true);
    setState(() => _saving = true);
    String? opt(TextEditingController c) => c.text.isEmpty ? null : c.text;
    try {
      await widget.session.farmClient.post('/api/Poultry/assets/${tStr(widget.asset['poultryCapitalAssetId'])}/costs',
          query: {'farmId': widget.company.farmId},
          body: {
            'costDate': _date.isEmpty ? null : _date,
            'description': opt(_desc),
            'costCategory': opt(_type),
            'amount': amount,
            'supplier': opt(_supplier),
            'paymentMethod': _method,
            'amountPaid': _paid.text.isEmpty ? null : num.tryParse(_paid.text),
            'dueDate': _due.isEmpty ? null : _due,
            'cashAccountId': _account.isEmpty ? null : int.parse(_account),
            'farmId': widget.company.farmId,
            'createdBy': widget.session.tokens.userId,
          });
      if (!mounted) return;
      trackerToast(context, 'Cost added', description: "The investment's value has increased. Nothing was charged to profit.");
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not add the cost', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.asset;
    final fmt = widget.fmt;
    final locked = tNum(a['depreciationEntries']) > 0;
    final expense = _treatment == 'expense';
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Text('Add cost to ${tStr(a['assetName'])}'),
        content: SizedBox(
          width: 580,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              'Cement, roofing, labour — real extra money spent on this investment, added to what it is worth. It currently stands at ${fmt(tNum(a['totalCapitalizedCost']))}'
              '${tNum(a['additionalCost']) > 0 ? ' (${fmt(tNum(a['acquisitionCost']))} acquired, ${fmt(tNum(a['additionalCost']))} added since).' : '.'}'
              ' To fix a wrong amount rather than record a new one, use Correct original cost instead.',
              style: const TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            formSection('How to treat it', _blue, [
              _hinted(
                'Cost treatment',
                AppSelect<String>(
                  value: _treatment,
                  items: const [
                    AppSelectItem(value: 'capitalise', label: 'Capitalise to this investment'),
                    AppSelectItem(value: 'expense', label: 'Record as an operating expense'),
                  ],
                  onChanged: (v) => setState(() => _treatment = v ?? 'capitalise'),
                ),
                costTreatmentNote,
              ),
            ]),
            const SizedBox(height: 12),
            if (expense)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: const Color(0xFFFDE68A)), borderRadius: BorderRadius.circular(6)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('An operating expense is recorded on the Expenses page',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TColors.amber900)),
                  const SizedBox(height: 4),
                  const Text(
                    "It will be charged in full against this period's profit and will NOT change what this investment is worth. Record it there and it behaves exactly like any other bill.",
                    style: TextStyle(fontSize: 12, color: TColors.amber900),
                  ),
                  const SizedBox(height: 8),
                  Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
                    OutlinedButton(onPressed: () => setState(() => _treatment = 'capitalise'), child: const Text('Back to capitalising')),
                    FilledButton(
                      onPressed: () {
                        Navigator.pop(context, false);
                        openAppHref(context, widget.session, widget.company, '/expenses', label: 'Expenses');
                      },
                      child: const Text('Go to Expenses'),
                    ),
                  ]),
                ]),
              )
            else ...[
              formSection('Cost', _blue, [
                FilterLabel('Date', _dateField(_date, (v) => setState(() => _date = v), clearable: true)),
                FilterLabel('Amount', _num(_amount, () => setState(() {}))),
                FilterLabel('What it was for', AppInput(controller: _desc, hintText: 'Roofing sheets')),
                FilterLabel('Cost type', AppInput(controller: _type, hintText: 'Materials / Labour')),
                FilterLabel('Supplier / payee', AppInput(controller: _supplier)),
                FilterLabel(
                  'Payment method',
                  AppSelect<String>(
                    value: _method,
                    items: [for (final m in const ['Cash', 'MoMo', 'Bank', 'Credit']) AppSelectItem(value: m, label: m)],
                    onChanged: (v) => setState(() => _method = v ?? 'Cash'),
                  ),
                ),
                _hinted('Amount paid now', _num(_paid, () => setState(() {})), 'Leave blank if paid in full.'),
                FilterLabel('Paid from', _accountSelect(widget.cashAccounts, _account, (v) => setState(() => _account = v))),
                _hinted('Balance due date', _dateField(_due, (v) => setState(() => _due = v), clearable: true), 'When the unpaid part falls due.'),
              ]),
              if (locked) ...[const SizedBox(height: 10), amberNote(costLockedByDepreciationNote)],
            ],
          ]),
        ),
        actions: expense
            ? null
            : [
                OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
                FilledButton(onPressed: _saving || locked ? null : _save, child: Text(_saving ? 'Saving…' : 'Add cost')),
              ],
      ),
    );
  }
}

/// Dispose: proceeds are money in, not sales revenue.
class DisposeAssetDialog extends StatefulWidget {
  const DisposeAssetDialog({super.key, required this.session, required this.company, required this.asset, required this.cashAccounts, required this.fmt});
  final Session session;
  final Company company;
  final Map asset;
  final List<Map> cashAccounts;
  final FarmMoney fmt;

  @override
  State<DisposeAssetDialog> createState() => _DisposeAssetDialogState();
}

class _DisposeAssetDialogState extends State<DisposeAssetDialog> {
  String _date = _today(), _account = '';
  final _proceeds = TextEditingController(), _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _proceeds.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Poultry/assets/${tStr(widget.asset['poultryCapitalAssetId'])}/dispose',
          query: {'farmId': widget.company.farmId},
          body: {
            'disposalDate': _date.isEmpty ? null : _date,
            'proceeds': _proceeds.text.isEmpty ? null : num.tryParse(_proceeds.text),
            'cashAccountId': _account.isEmpty ? null : int.parse(_account),
            'notes': _notes.text.isEmpty ? null : _notes.text,
            'farmId': widget.company.farmId,
            'createdBy': widget.session.tokens.userId,
          });
      if (!mounted) return;
      trackerToast(context, 'Investment disposed');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not dispose the investment', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: AlertDialog(
          scrollable: true,
          title: Text('Dispose of ${tStr(widget.asset['assetName'])}'),
          content: SizedBox(
            width: 500,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                'Its book value today is ${widget.fmt(tNum(widget.asset['currentBookValue']))}. Sale proceeds are recorded as money IN and are not sales revenue.',
                style: const TextStyle(fontSize: 13, color: TColors.slate500),
              ),
              const SizedBox(height: 12),
              formSection('Disposal', _blue, [
                FilterLabel('Date', _dateField(_date, (v) => setState(() => _date = v), clearable: true)),
                _hinted('Proceeds', _num(_proceeds, () => setState(() {})), 'Leave blank if nothing was received.'),
                FilterLabel('Received into', _accountSelect(widget.cashAccounts, _account, (v) => setState(() => _account = v))),
                FilterLabel('Notes', AppInput(controller: _notes, minLines: 2, maxLines: 4)),
              ]),
              const SizedBox(height: 8),
              const Text(
                'Gain or loss on disposal — the difference between the proceeds and the book value — is not yet calculated. It is recorded here as a cash receipt only.',
                style: TextStyle(fontSize: 11, color: TColors.slate500),
              ),
            ]),
          ),
          actions: [
            OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Dispose')),
          ],
        ),
      );
}

/// Reverse an acquisition: kept and marked reversed, cash paid returned.
class ReverseAssetDialog extends StatefulWidget {
  const ReverseAssetDialog({super.key, required this.session, required this.company, required this.asset});
  final Session session;
  final Company company;
  final Map asset;

  @override
  State<ReverseAssetDialog> createState() => _ReverseAssetDialogState();
}

class _ReverseAssetDialogState extends State<ReverseAssetDialog> {
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_reason.text.trim().isEmpty) return trackerToast(context, 'A reason is required', error: true);
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Poultry/assets/${tStr(widget.asset['poultryCapitalAssetId'])}/reverse',
          query: {'farmId': widget.company.farmId},
          body: {'farmId': widget.company.farmId, 'reason': _reason.text.trim(), 'createdBy': widget.session.tokens.userId});
      if (!mounted) return;
      trackerToast(context, 'Acquisition reversed', description: 'Any cash paid has been returned. The record is kept with its reason.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not reverse the investment', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: AlertDialog(
          scrollable: true,
          title: Text('Reverse ${tStr(widget.asset['assetName'])}'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text(
                'The investment and its costs are kept and marked reversed; any cash paid is returned to its account. This is refused if depreciation has been posted or a supplier payment has been recorded against it.',
                style: TextStyle(fontSize: 13, color: TColors.slate500),
              ),
              const SizedBox(height: 12),
              FilterLabel('Reason', AppInput(controller: _reason, minLines: 3, maxLines: 5, hintText: 'Recorded on the wrong company')),
            ]),
          ),
          actions: [
            OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: TColors.red600, foregroundColor: Colors.white),
              child: Text(_saving ? 'Saving…' : 'Reverse'),
            ),
          ],
        ),
      );
}
