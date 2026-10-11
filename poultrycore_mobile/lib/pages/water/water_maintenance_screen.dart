import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart';
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';

/// Water → Operations → Production → Maintenance, as
/// `app/water-maintenance/page.tsx`: the due-maintenance alerts, the issue
/// log, Log issue, Complete (optionally booking the cash out) and Delete.

const waterMaintenanceAssetTypes = ['Machine', 'Vehicle', 'Borehole', 'Generator', 'Other'];

Widget waterMaintenanceStatusBadge(Object? status) {
  final s = tStr(status);
  final (bg, fg) = switch (s) {
    'Open' => (TColors.amber100, TColors.amber700),
    'InProgress' => (TColors.blue100, const Color(0xFF1D4ED8)),
    'Completed' => (const Color(0xFFDCFCE7), const Color(0xFF15803D)),
    _ => (TColors.slate100, TColors.slate700),
  };
  return TBadge(s, bg: bg, fg: fg);
}

Widget waterSeverityBadge(Object? severity) {
  final s = tStr(severity);
  final (bg, fg) = switch (s) {
    'Overdue' => (const Color(0xFFFFE4E6), const Color(0xFFBE123C)),
    'DueSoon' => (TColors.amber100, TColors.amber700),
    'Upcoming' => (TColors.blue100, const Color(0xFF1D4ED8)),
    _ => (TColors.slate100, TColors.slate700),
  };
  return TBadge(s, bg: bg, fg: fg);
}

/// "in 3d" / "2d ago".
String waterDueIn(num days) => days >= 0 ? 'in ${days.toInt()}d' : '${days.abs().toInt()}d ago';

/// filterByDateAndSearch on issueDate, searching asset, issue and technician.
List<Map> filterWaterMaintenance(List<Map> rows, {String search = '', String from = '', String to = ''}) {
  final q = search.trim().toLowerCase();
  return rows.where((r) {
    final day = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(tStr(r['issueDate']))?[1];
    if (day != null) {
      if (from.isNotEmpty && day.compareTo(from) < 0) return false;
      if (to.isNotEmpty && day.compareTo(to) > 0) return false;
    }
    if (q.isNotEmpty && !['assetLabel', 'issueDescription', 'technicianName'].any((k) => r[k] != null && '${r[k]}'.toLowerCase().contains(q))) {
      return false;
    }
    return true;
  }).toList();
}

class WaterMaintenanceScreen extends StatefulWidget {
  const WaterMaintenanceScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<WaterMaintenanceScreen> createState() => _WaterMaintenanceScreenState();
}

class _WaterMaintenanceScreenState extends State<WaterMaintenanceScreen> {
  List<Map> _logs = [], _alerts = [], _accounts = [];
  bool _loading = true;
  final _search = TextEditingController();
  String _from = '', _to = '';
  int _page = 1, _pageSize = 10, _lastTotal = -1;
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  @override
  void initState() {
    super.initState();
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
    try {
      final r = await Future.wait([
        _api.get('/api/Water/maintenance-logs', query: q),
        _api.get('/api/Water/maintenance-logs/due-alerts', query: q),
        _api.get('/api/Water/cash-accounts', query: q),
      ]);
      if (!mounted) return;
      setState(() {
        _logs = rowsOf(r[0]);
        _alerts = rowsOf(r[1]);
        _accounts = rowsOf(r[2]);
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load maintenance logs', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  int _id(Map l) => tIntOrNull(l['waterMaintenanceLogId']) ?? 0;
  bool _open(Map l) => tStr(l['status']) != 'Completed' && tStr(l['status']) != 'Cancelled';

  Future<void> _logIssue() async {
    final done = await showDialog<bool>(context: context, builder: (_) => WaterMaintenanceLogDialog(session: widget.session, company: widget.company));
    if (done == true) await _load();
  }

  Future<void> _complete(Map l) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _CompleteDialog(session: widget.session, company: widget.company, log: l, accounts: _accounts),
    );
    if (done == true) await _load();
  }

  Future<void> _delete(Map l) async {
    final ok = await confirmDelete(
      context,
      title: 'Delete maintenance log?',
      description:
          'Delete the log for "${tStr(l['assetLabel']).isNotEmpty ? tStr(l['assetLabel']) : tStr(l['assetType'])}"? This action cannot be undone.',
    );
    if (!ok) return;
    try {
      await _api.delete('/api/Water/maintenance-logs/${_id(l)}', query: {'farmId': _farmId});
      if (mounted) trackerToast(context, 'Log deleted');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Delete failed', description: e.message, error: true);
    }
  }

  List<Widget> _actions(Map l) => [
        if (_open(l))
          OutlinedButton.icon(
            onPressed: () => _complete(l),
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF15803D), side: const BorderSide(color: Color(0xFFBBF7D0))),
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('Complete'),
          ),
        OutlinedButton(
          onPressed: () => _delete(l),
          style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: Color(0xFFFECACA))),
          child: const Text('Delete'),
        ),
      ];

  Widget _alertsCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: const Color(0xFFFDE68A)), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Due maintenance (${_alerts.length})', style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.amber900)),
          const SizedBox(height: 8),
          for (final a in _alerts)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(4)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(text: tStr(a['assetLabel']), style: const TextStyle(fontWeight: FontWeight.w500)),
                      TextSpan(text: ' (${tStr(a['assetType'])})', style: const TextStyle(fontSize: 12, color: TColors.slate400)),
                    ])),
                    Text('Due ${fmtDateTime(a['nextDueDate'], null, _offset)} (${waterDueIn(tNum(a['daysUntilDue']))})',
                        style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  ]),
                ),
                waterSeverityBadge(a['severity']),
              ]),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/water-maintenance');
    final visible = filterWaterMaintenance(_logs, search: _search.text, from: _from, to: _to);
    if (visible.length != _lastTotal) {
      _lastTotal = visible.length;
      _page = 1;
    }
    final pageRows = pageSlice(visible, _page, _pageSize);
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Maintenance')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.build_outlined, color: Color(0xFF0284C7)),
              SizedBox(width: 8),
              Flexible(child: Text('Maintenance', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _logIssue,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Log issue'),
            ),
            const SizedBox(height: 12),
            if (_alerts.isNotEmpty) ...[_alertsCard(), const SizedBox(height: 12)],
            ListFiltersCard(
              search: _search,
              searchPlaceholder: 'Search asset, issue or technician',
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
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading…'))
            else if (_logs.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                child: const Text('No maintenance logs yet.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
              )
            else
              MobileCardList<Map>(
                striped: true,
                items: pageRows,
                keyOf: (l) => '${_id(l)}',
                primary: (l) => '${tStr(l['assetType'])} · ${tStr(l['assetLabel']).isEmpty ? '—' : tStr(l['assetLabel'])}',
                secondaryBuilder: (l) => Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(fmtDateTime(l['issueDate'], l, _offset)),
                  waterMaintenanceStatusBadge(l['status']),
                ]),
                highlights: (l) => [Highlight('Repair cost', tNum(l['repairCost']).toStringAsFixed(2), accent: Accent.rose, wide: true)],
                details: (l) => [
                  ('Date', fmtDateTime(l['issueDate'], l, _offset)),
                  ('Asset', '${tStr(l['assetType'])} ${tStr(l['assetLabel'])}'),
                  ('Technician', tStr(l['technicianName']).isEmpty ? '—' : tStr(l['technicianName'])),
                  ('Status', tStr(l['status'])),
                  ('Issue', tStr(l['issueDescription'])),
                ],
                actions: _actions,
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Date', width: 130), TCol('Asset', width: 170), TCol('Issue', width: 220), TCol('Technician', width: 120),
                    TCol('Cost', right: true, width: 90), TCol('Status', width: 130), TCol('Actions', right: true, width: 100),
                  ],
                  rows: [
                    for (final l in items)
                      [
                        cellText(fmtDateTime(l['issueDate'], l, _offset)),
                        Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          TBadge(tStr(l['assetType']), bg: Colors.white, fg: TColors.slate700, border: TColors.slate300),
                          Text(tStr(l['assetLabel'])),
                        ]),
                        Text(tStr(l['issueDescription'])),
                        cellText(tStr(l['technicianName']).isEmpty ? '—' : tStr(l['technicianName'])),
                        Align(alignment: Alignment.centerRight, child: cellText(tNum(l['repairCost']).toStringAsFixed(2))),
                        Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          waterMaintenanceStatusBadge(l['status']),
                          if (l['cashTransactionWritten'] == true) const Text('💸', style: TextStyle(fontSize: 12)),
                        ]),
                        Wrap(alignment: WrapAlignment.end, children: [
                          if (_open(l))
                            IconButton(
                              tooltip: 'Complete',
                              onPressed: () => _complete(l),
                              icon: const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF16A34A)),
                            ),
                          IconButton(tooltip: 'Delete', onPressed: () => _delete(l), icon: const Text('×', style: TextStyle(fontSize: 18))),
                        ]),
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

/// Log maintenance issue.
class WaterMaintenanceLogDialog extends StatefulWidget {
  const WaterMaintenanceLogDialog({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<WaterMaintenanceLogDialog> createState() => _WaterMaintenanceLogDialogState();
}

class _WaterMaintenanceLogDialogState extends State<WaterMaintenanceLogDialog> {
  String _type = 'Machine';
  final _label = TextEditingController(), _issue = TextEditingController(), _tech = TextEditingController();
  final _cost = TextEditingController(text: '0'), _downtime = TextEditingController(), _parts = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_label, _issue, _tech, _cost, _downtime, _parts, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_issue.text.trim().isEmpty) return trackerToast(context, 'Issue description required', error: true);
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Water/maintenance-logs', body: {
        'assetType': _type,
        'assetId': null,
        'assetLabel': _label.text,
        'issueDescription': _issue.text,
        'technicianName': _tech.text,
        'repairCost': num.tryParse(_cost.text) ?? 0,
        'partsReplaced': _parts.text,
        'downtimeHours': _downtime.text.isEmpty ? null : num.tryParse(_downtime.text),
        'notes': _notes.text,
        'farmId': widget.company.farmId,
        'createdBy': widget.session.tokens.userId,
      });
      if (!mounted) return;
      trackerToast(context, 'Maintenance logged');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Save failed', description: e.message, error: true);
    }
  }

  Widget _num(TextEditingController c) => AppInput(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
      );

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: AlertDialog(
          scrollable: true,
          title: const Row(children: [
            Icon(Icons.build_outlined, size: 20, color: Color(0xFF2563EB)),
            SizedBox(width: 8),
            Flexible(child: Text('Log maintenance issue')),
          ]),
          content: SizedBox(
            width: 600,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Record a maintenance issue or repair', style: TextStyle(fontSize: 13, color: TColors.slate500)),
              const SizedBox(height: 12),
              formSection('Asset', const Color(0xFF4F46E5), [
                FilterLabel(
                  'Asset type',
                  AppSelect<String>(
                    value: _type,
                    items: [for (final t in waterMaintenanceAssetTypes) AppSelectItem(value: t, label: t)],
                    onChanged: (v) => setState(() => _type = v ?? 'Machine'),
                  ),
                ),
                FilterLabel('Asset label / name', AppInput(controller: _label, hintText: 'e.g. Truck 1, Genset')),
                FilterLabel('Issue description *', AppInput(controller: _issue, minLines: 3, maxLines: 6)),
              ]),
              const SizedBox(height: 12),
              formSection('Repair details', const Color(0xFF2563EB), [
                FilterLabel('Technician', AppInput(controller: _tech)),
                FilterLabel('Repair cost', _num(_cost)),
                FilterLabel('Downtime hours', _num(_downtime)),
                FilterLabel('Parts replaced', AppInput(controller: _parts)),
              ]),
              const SizedBox(height: 12),
              formSection('Notes', TColors.slate600, [FilterLabel('Notes', AppInput(controller: _notes, minLines: 3, maxLines: 6))]),
            ]),
          ),
          actions: [
            redCancelButton(_saving ? null : () => Navigator.pop(context, false)),
            FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Log')),
          ],
        ),
      );
}

class _CompleteDialog extends StatefulWidget {
  const _CompleteDialog({required this.session, required this.company, required this.log, required this.accounts});
  final Session session;
  final Company company;
  final Map log;
  final List<Map> accounts;

  @override
  State<_CompleteDialog> createState() => _CompleteDialogState();
}

class _CompleteDialogState extends State<_CompleteDialog> {
  int? _cashId;

  Future<void> _complete() async {
    try {
      await widget.session.farmClient.post(
        '/api/Water/maintenance-logs/${tStr(widget.log['waterMaintenanceLogId'])}/complete',
        query: {'farmId': widget.company.farmId, 'completedBy': widget.session.tokens.userId ?? ''},
        body: {'waterCashAccountId': _cashId},
      );
      if (!mounted) return;
      trackerToast(context, 'Marked completed${_cashId != null ? ' — cash booked' : ''}');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Complete failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: const Row(children: [
          Icon(Icons.check_circle_outline, size: 20, color: Color(0xFF16A34A)),
          SizedBox(width: 8),
          Flexible(child: Text('Complete maintenance')),
        ]),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Mark this log completed and optionally book the cash impact', style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Cost: '),
                TextSpan(text: tNum(widget.log['repairCost']).toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w600)),
                const TextSpan(text: '. Picking a cash account will book a CashOut at the same time.'),
              ]),
              style: const TextStyle(fontSize: 13, color: TColors.slate600),
            ),
            const SizedBox(height: 12),
            formSection('Cash impact', TColors.amber600, [
              FilterLabel(
                'Cash account (optional)',
                AppSelect<int>(
                  value: _cashId,
                  hintText: 'None (no cash impact)',
                  items: [
                    for (final a in widget.accounts)
                      if (a['isActive'] == true)
                        AppSelectItem(
                          value: tIntOrNull(a['waterCashAccountId']) ?? 0,
                          label: '${tStr(a['accountName'])} (${tNum(a['currentBalance']).toStringAsFixed(2)})',
                        ),
                  ],
                  onChanged: (v) => setState(() => _cashId = v),
                ),
              ),
            ]),
          ]),
        ),
        actions: [
          redCancelButton(() => Navigator.pop(context, false)),
          FilledButton(onPressed: _complete, child: const Text('Mark completed')),
        ],
      );
}
