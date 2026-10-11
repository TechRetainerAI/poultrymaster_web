// Settings → Activity Log (app/audit-logs/page.tsx): "Audit Logs" — search,
// the Filters sheet (status, action, resource, user, from / to), the Audit
// Trail cards and table, paging, and "View data".

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/production/production_records_screen.dart' show ProdCard;
import '../poultry/sales/balances_widgets.dart' show CompactPager;
import '../poultry/trackers/tracker_logic.dart' show tStr, trackerDate, sortRows, toggleSort, SortState;
import '../poultry/trackers/tracker_widgets.dart';

/// friendlyAction: the HTTP verb as a word.
String friendlyAction(Object? method) => switch (tStr(method).toUpperCase()) {
      'GET' => 'Viewed',
      'POST' => 'Created',
      'PUT' => 'Updated',
      'DELETE' => 'Deleted',
      _ => tStr(method),
    };

String prettyAuditData(Object? raw) {
  final s = tStr(raw);
  if (s.isEmpty) return '—';
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(s));
  } catch (_) {
    return s;
  }
}

String _localeString(Object? v) {
  final d = DateTime.tryParse(tStr(v))?.toLocal();
  if (d == null) return tStr(v);
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${d.month}/${d.day}/${d.year}, $h:${two(d.minute)}:${two(d.second)} ${d.hour < 12 ? 'AM' : 'PM'}';
}

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  List<Map> _logs = [];
  bool _loading = true, _table = false;
  String _error = '', _q = '', _status = 'All', _action = 'All', _resource = 'All', _user = 'All', _from = '', _to = '';
  final _search = TextEditingController();
  SortState _sort = (key: null, dir: null);
  int _page = 1, _size = 10;

  ApiClient get _api => widget.session.farmClient;

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

  List<Map> _normalise(Object? res) {
    if (res is List) return rowsOf(res);
    if (res is Map) {
      for (final k in ['items', 'data', 'result']) {
        if (res[k] is List) return rowsOf(res[k]);
      }
    }
    return [];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    final farmId = widget.company.farmId;
    if (farmId.isEmpty) {
      setState(() {
        _error = 'Farm ID not found. Please log in again.';
        _loading = false;
      });
      return;
    }
    try {
      final all = <Map>[];
      for (var page = 1; page <= 100; page++) {
        final batch = _normalise(await _api
            .get('/api/AuditLogs', query: {'page': '$page', 'pageSize': '500', 'farmId': farmId})
            .timeout(const Duration(seconds: 45)));
        if (batch.isEmpty) break;
        all.addAll(batch);
        if (batch.length < 500) break;
      }
      if (mounted) setState(() => _logs = all);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = 'HTTP ${e.statusCode}: ${e.message.isNotEmpty ? e.message : (e.statusCode == 500 ? 'Farm API error (500). Common fix: run SQL migration 007_AddAuditLogsFarmId.sql so dbo.AuditLogs has a FarmId column, then redeploy the Farm API.' : 'HTTP ${e.statusCode}')}';
          _logs = [];
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Request timed out after 45s. The Farm API may be cold-starting or the network is slow. Wait a moment and refresh, or check Cloud Run logs for poultrymaster-farm-api-git.';
          _logs = [];
        });
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  String _displayUser(Object? name) {
    final n = tStr(name);
    if (n.isNotEmpty && n.toLowerCase() != 'unknown') return n;
    final local = widget.session.tokens.username ?? '';
    return local.isNotEmpty ? local : 'Unknown';
  }

  List<String> _options(String k) => ({for (final l in _logs) if (tStr(l[k]).trim().isNotEmpty) tStr(l[k]).trim()}.toList()..sort());

  String _dayKey(Object? ts) {
    final d = DateTime.tryParse(tStr(ts))?.toLocal();
    return d == null ? '' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  List<Map> get _filtered {
    final q = _q.trim().toLowerCase();
    return [
      for (final l in _logs)
        if ((q.isEmpty || ['action', 'resource', 'userName', 'details', 'resourceId', 'ipAddress'].any((k) => tStr(l[k]).toLowerCase().contains(q))) &&
            (_status == 'All' || tStr(l['status']) == _status) &&
            (_action == 'All' || tStr(l['action']) == _action) &&
            (_resource == 'All' || tStr(l['resource']) == _resource) &&
            (_user == 'All' || tStr(l['userName']) == _user) &&
            (_from.isEmpty || (_dayKey(l['timestamp']).isNotEmpty && _dayKey(l['timestamp']).compareTo(_from) >= 0)) &&
            (_to.isEmpty || (_dayKey(l['timestamp']).isNotEmpty && _dayKey(l['timestamp']).compareTo(_to) <= 0)))
          l,
    ];
  }

  void _clear() => setState(() {
        _search.clear();
        _q = '';
        _status = 'All';
        _action = 'All';
        _resource = 'All';
        _user = 'All';
        _from = '';
        _to = '';
        _page = 1;
      });

  void _viewData(Map log) => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Audit log data'),
          content: SizedBox(
            width: 640,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${friendlyAction(log['action'])} ${tStr(log['resource'])} • ${_localeString(log['timestamp'])} • ${_displayUser(log['userName'])}',
                  style: const TextStyle(fontSize: 14, color: TColors.slate500)),
              const SizedBox(height: 10),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
                  child: SingleChildScrollView(
                    child: SelectableText(prettyAuditData(log['data']), style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: TColors.slate800)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        void upd(VoidCallback f) {
          setState(f);
          set(() {});
        }

        Widget statusBtn(String s) => _status == s
            ? FilledButton(onPressed: () => upd(() => _status = s), child: Text(s))
            : OutlinedButton(onPressed: () => upd(() => _status = s), child: Text(s));
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Filters', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              FilterLabel('Status', Wrap(spacing: 8, children: [statusBtn('All'), statusBtn('Success'), statusBtn('Failed')])),
              const SizedBox(height: 12),
              FilterLabel(
                'Action',
                AppSelect<String>(
                  value: _action,
                  items: [const AppSelectItem(value: 'All', label: 'All actions'), for (final a in _options('action')) AppSelectItem(value: a, label: friendlyAction(a))],
                  onChanged: (v) => upd(() => _action = v ?? 'All'),
                ),
              ),
              const SizedBox(height: 12),
              FilterLabel(
                'Resource',
                AppSelect<String>(
                  value: _resource,
                  items: [const AppSelectItem(value: 'All', label: 'All resources'), for (final r in _options('resource')) AppSelectItem(value: r, label: r)],
                  onChanged: (v) => upd(() => _resource = v ?? 'All'),
                ),
              ),
              const SizedBox(height: 12),
              FilterLabel(
                'User',
                AppSelect<String>(
                  value: _user,
                  items: [const AppSelectItem(value: 'All', label: 'All users'), for (final u in _options('userName')) AppSelectItem(value: u, label: u)],
                  onChanged: (v) => upd(() => _user = v ?? 'All'),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: FilterLabel('From', FilterDate(value: _from, hint: 'From', onChanged: (v) => upd(() => _from = v)))),
                const SizedBox(width: 10),
                Expanded(child: FilterLabel('To', FilterDate(value: _to, hint: 'To', onChanged: (v) => upd(() => _to = v)))),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => upd(_clear), child: const Text('Clear'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Apply'))),
              ]),
            ]),
          ),
        );
      }),
    );
  }

  Widget _statusBadge(Object? s) =>
      tStr(s) == 'Success' ? TBadge(tStr(s), bg: TColors.slate900, fg: Colors.white) : TBadge(tStr(s), bg: TColors.red600, fg: Colors.white);

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/audit-logs');
    final rows = sortRows(_filtered, _sort, (r, k) => k == 'timestamp' ? (DateTime.tryParse(tStr(r['timestamp'])) ?? DateTime(0)) : tStr(r[k]));
    final pages = rows.isEmpty ? 1 : (rows.length + _size - 1) ~/ _size;
    final page = _page.clamp(1, pages);
    final pageRows = rows.skip((page - 1) * _size).take(_size).toList();
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Audit Logs')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 28), children: [
          const Text('Audit Logs', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
          const Text('Track all user activities and system events', style: TextStyle(fontSize: 14, color: TColors.slate600)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: AppInput(
                controller: _search,
                hintText: 'Search logs...',
                prefixIcon: const Icon(Icons.search, size: 18, color: TColors.slate400),
                onChanged: (v) => setState(() {
                  _q = v;
                  _page = 1;
                }),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: _openFilters, icon: const Icon(Icons.filter_list, size: 16), label: const Text('Filters')),
            const SizedBox(width: 8),
            // As on the web: the download button has no action wired to it.
            IconButton.outlined(onPressed: () {}, icon: const Icon(Icons.download_outlined, size: 18)),
          ]),
          const SizedBox(height: 16),
          TCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Audit Trail', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: TColors.slate900)),
              const Text('Recent system activities and user actions', style: TextStyle(fontSize: 14, color: TColors.slate500)),
              const SizedBox(height: 14),
              if (_loading)
                const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Text('Loading logs...', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)))
              else if (_error.isNotEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFEF4444))))
              else if (rows.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Text('No audit logs found', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)))
              else if (!_table) ...[
                for (var i = 0; i < pageRows.length; i++) ...[_card(pageRows[i], i), const SizedBox(height: 10)],
                ViewTableButton(onPressed: () => setState(() => _table = true)),
              ] else ...[
                TableViewBar(text: 'Table • Scroll → for more', onCards: () => setState(() => _table = false)),
                TrackerTable(
                  sort: _sort,
                  onSort: (k) => setState(() => _sort = toggleSort(k, _sort)),
                  columns: const [
                    TCol('Timestamp', sortKey: 'timestamp', width: 110),
                    TCol('User', sortKey: 'userName', width: 140),
                    TCol('Action', sortKey: 'action', width: 90),
                    TCol('Resource', sortKey: 'resource', width: 140),
                    TCol('IP Address', sortKey: 'ipAddress', width: 120),
                    TCol('Status', sortKey: 'status', width: 90),
                    TCol('Details', width: 220),
                    TCol('Data', width: 90),
                  ],
                  rows: [
                    for (final l in pageRows)
                      [
                        Text(trackerDate(l['timestamp']), style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                        cellText(_displayUser(l['userName'])),
                        cellText(friendlyAction(l['action']), bold: true),
                        cellText(tStr(l['resource'])),
                        Text(tStr(l['ipAddress']), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        Align(alignment: Alignment.centerLeft, child: _statusBadge(l['status'])),
                        Text(tStr(l['details']), maxLines: 1, overflow: TextOverflow.ellipsis),
                        tStr(l['data']).isNotEmpty
                            ? InkWell(onTap: () => _viewData(l), child: const Text('View data', style: TextStyle(fontWeight: FontWeight.w500, color: TColors.blue600)))
                            : cellText('—'),
                      ],
                  ],
                ),
              ],
              if (!_loading && _error.isEmpty && rows.isNotEmpty)
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
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _card(Map l, int i) {
    Widget kv(String k, String v, {bool mono = false}) => Text.rich(TextSpan(children: [
          TextSpan(text: '$k ', style: const TextStyle(color: TColors.slate500)),
          TextSpan(text: v, style: TextStyle(fontWeight: FontWeight.w500, fontFamily: mono ? 'monospace' : null, fontSize: mono ? 12 : null)),
        ]), style: const TextStyle(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis);
    return ProdCard(
      key: ValueKey('log-${l['id']}'),
      striped: i.isEven,
      header: Padding(
        padding: const EdgeInsets.only(right: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(trackerDate(l['timestamp']), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _statusBadge(l['status']),
            Text(_displayUser(l['userName']), style: const TextStyle(color: TColors.slate600)),
            Text(friendlyAction(l['action']), style: const TextStyle(color: TColors.slate500)),
          ]),
        ]),
      ),
      body: LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - 8) / 2;
        return Wrap(spacing: 8, runSpacing: 6, children: [
          SizedBox(width: w, child: kv('Resource', tStr(l['resource']))),
          SizedBox(width: w, child: kv('IP', tStr(l['ipAddress']), mono: true)),
          if (tStr(l['details']).isNotEmpty) SizedBox(width: c.maxWidth, child: kv('Details', tStr(l['details']))),
          if (tStr(l['data']).isNotEmpty)
            SizedBox(
              width: c.maxWidth,
              child: Row(children: [
                const Text('Data', style: TextStyle(fontSize: 14, color: TColors.slate500)),
                const SizedBox(width: 8),
                InkWell(onTap: () => _viewData(l), child: const Text('View data', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.blue600))),
              ]),
            ),
        ]);
      }),
    );
  }
}
