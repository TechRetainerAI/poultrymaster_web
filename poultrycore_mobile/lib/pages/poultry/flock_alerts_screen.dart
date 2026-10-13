import 'dart:convert';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';
import 'flock_alerts_logic.dart';
import 'poultry_links.dart';
import 'sales/balances_widgets.dart' show LoadingLine;
import 'trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import 'trackers/tracker_widgets.dart';

/// Poultry → Tools → Flock Alerts, as `app/poultry-flock-alerts/page.tsx`
/// (migration 338): each flock's figures today against its own recent history,
/// with the numbers behind every alert. Alerts / Daily checks, the alert's own
/// panel (the web's side sheet, a page here) and Alert settings.

const _rose100 = Color(0xFFFFE4E6);

/// FlockAlertsController.
class FlockAlertsApi {
  FlockAlertsApi(this.session, this.company);
  final Session session;
  final Company company;
  ApiClient get _c => session.farmClient;
  String get farmId => company.farmId;
  static const base = '/api/Poultry/flock-alerts';

  Future<Object?> list(String status) => _c.get(base, query: {'farmId': farmId, 'status': status});
  Future<Object?> get(int id) => _c.get('$base/$id', query: {'farmId': farmId});
  Future<Object?> evaluation(String? date) =>
      _c.get('$base/evaluation', query: {'farmId': farmId, if (date != null && date.isNotEmpty) 'date': date});
  Future<Object?> rescan(String from, String to) => _c.post('$base/scan', body: {'farmId': farmId, 'from': from, 'to': to});
  Future<Object?> acknowledge(int id, String? note) => _c.post('$base/$id/acknowledge', body: {'farmId': farmId, 'note': note});
  Future<Object?> addNote(int id, String note) => _c.post('$base/$id/notes', body: {'farmId': farmId, 'note': note});
  Future<Object?> resolve(int id, String note) => _c.post('$base/$id/resolve', body: {'farmId': farmId, 'note': note});
  Future<Object?> settings() => _c.get('$base/settings', query: {'farmId': farmId});
  Future<Object?> saveSetting(Map s) => _c.put('$base/settings', body: {...s, 'farmId': farmId});
  Future<Object?> resetSetting(String key) => _c.put('$base/settings/reset', body: {'farmId': farmId, 'signalKey': key});
}

/// FILTERS: (value, label).
const alertFilters = [
  ('active', 'Needs attention'),
  ('Resolved', 'Resolved'),
  ('Cleared', 'Cleared by data'),
  ('all', 'All'),
];

Widget severityBadge(Object? severity, {double size = 11}) {
  final st = alertSeverityStyle(severity);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: st.bg, border: Border.all(color: st.border), borderRadius: BorderRadius.circular(999)),
    child: Text(st.label.toUpperCase(), style: TextStyle(fontSize: size, fontWeight: FontWeight.w500, color: st.fg)),
  );
}

Widget alertStatusBadge(Object? status) {
  final st = alertStatusStyle(status);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: st.border), borderRadius: BorderRadius.circular(999)),
    child: Text(st.label, style: TextStyle(fontSize: 11, color: st.fg)),
  );
}

/// The web's segmented filter: a slate pill, the chosen one white.
Widget _segments<T>(List<(T, String)> options, T value, ValueChanged<T> onChanged, {bool dark = false}) => Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: dark ? Colors.white : TColors.slate50,
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Wrap(children: [
        for (final (v, l) in options)
          InkWell(
            onTap: () => onChanged(v),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: v == value ? (dark ? TColors.slate900 : Colors.white) : null,
                borderRadius: BorderRadius.circular(4),
                boxShadow: v == value && !dark ? const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))] : null,
              ),
              child: Text(l,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: v == value && !dark ? FontWeight.w500 : FontWeight.w400,
                    color: v == value ? (dark ? Colors.white : TColors.slate900) : TColors.slate600,
                  )),
            ),
          ),
      ]),
    );

class FlockAlertsScreen extends StatefulWidget {
  const FlockAlertsScreen({super.key, required this.session, required this.company, this.openAlertId});
  final Session session;
  final Company company;

  /// `?alert=`: opens that alert straight away.
  final int? openAlertId;

  @override
  State<FlockAlertsScreen> createState() => _FlockAlertsScreenState();
}

class _FlockAlertsScreenState extends State<FlockAlertsScreen> {
  late final _api = FlockAlertsApi(widget.session, widget.company);
  String _tab = 'alerts';
  String _filter = 'active';
  List<Map>? _alerts;
  String? _error;
  bool _rescanning = false;

  @override
  void initState() {
    super.initState();
    _load();
    final id = widget.openAlertId;
    if (id != null) WidgetsBinding.instance.addPostFrameCallback((_) => _openAlert(id));
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await _api.list(_filter);
      if (mounted) setState(() => _alerts = sortAlerts(rowsOf(r)));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : 'Could not load flock alerts.');
    }
  }

  Future<void> _rescan() async {
    setState(() => _rescanning = true);
    try {
      // As the web: the last 14 days by the device's UTC date.
      final to = DateTime.now().toUtc();
      final from = to.subtract(const Duration(days: 13));
      String iso(DateTime d) => d.toIso8601String().substring(0, 10);
      await _api.rescan(iso(from), iso(to));
      if (mounted) trackerToast(context, 'Re-checked the last 14 days');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Re-check failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _rescanning = false);
  }

  Future<void> _openAlert(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FlockAlertScreen(session: widget.session, company: widget.company, alertId: id, onChanged: _load),
    ));
  }

  Future<void> _settings() async {
    await showDialog<void>(context: context, builder: (_) => _SettingsDialog(api: _api, onSaved: _load));
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-flock-alerts');
    final alerts = _alerts;
    final s = summarizeAlerts(alerts ?? const []);
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Flock Alerts')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: _rose100, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.monitor_heart_outlined, size: 20, color: TColors.rose700),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Flock Alerts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
                  Text("Each flock's figures today against its own recent history — with the numbers behind every alert.",
                      style: TextStyle(fontSize: 13, color: TColors.slate600)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Tooltip(
                message: 'Re-check the last 14 days, e.g. after correcting back-dated records',
                child: OutlinedButton.icon(
                  onPressed: _rescanning ? null : _rescan,
                  icon: _rescanning
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh, size: 16),
                  label: const Text('Re-check'),
                ),
              ),
              OutlinedButton.icon(onPressed: _settings, icon: const Icon(Icons.tune, size: 16), label: const Text('Alert settings')),
            ]),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: _segments(const [('alerts', 'Alerts'), ('checks', 'Daily checks')], _tab, (v) => setState(() => _tab = v), dark: true),
            ),
            const SizedBox(height: 12),
            if (_tab == 'alerts') ...[
              _segments(alertFilters, _filter, (v) {
                setState(() {
                  _filter = v;
                  _alerts = null;
                });
                _load();
              }),
              if (alerts != null && _filter == 'active') ...[
                const SizedBox(height: 8),
                Text('${s.critical} critical · ${s.warning} warning · ${s.information} information',
                    style: const TextStyle(fontSize: 13, color: TColors.slate600)),
              ],
              const SizedBox(height: 12),
              if (_error != null) TCard(child: Text(_error!, style: const TextStyle(fontSize: 13, color: TColors.rose700))),
              if (alerts == null && _error == null) const LoadingLine('Checking flocks…'),
              if (alerts != null && alerts.isEmpty)
                TCard(
                  child: Text(
                    _filter == 'active'
                        ? 'No flock needs attention. Every flock with a record is within its normal range, or does not yet have enough history to judge — see Daily checks.'
                        : 'Nothing here.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: TColors.slate600),
                  ),
                ),
              for (final a in alerts ?? const <Map>[]) ...[
                _AlertRow(alert: a, onOpen: () => _openAlert(tIntOrNull(a['alertId']) ?? 0)),
                const SizedBox(height: 8),
              ],
            ] else
              _DailyChecks(api: _api),
          ],
        ),
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert, required this.onOpen});
  final Map alert;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final a = alert;
    final sev = alertSeverityStyle(a['severity']);
    final signals = alertSignals(a);
    final active = signals.where((x) => x['isActive'] == true);
    final lead = active.isNotEmpty ? active.first : (signals.isNotEmpty ? signals.first : null);
    final days = tNum(a['consecutiveDays']).toInt();
    final notes = tNum(a['noteCount']).toInt();
    final edge = isActiveAlertStatus(a['status']) ? sev.edge : TColors.slate300;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 4, color: edge),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      severityBadge(a['severity']),
                      alertStatusBadge(a['status']),
                      Text(alertFlockLabel(a), style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
                      Text(formatLongDate(alertDay(a['businessDate'])), style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                      if (days > 1) TBadge('$days days in a row', bg: TColors.slate100, fg: TColors.slate700),
                    ]),
                    const SizedBox(height: 4),
                    Text(alertHeadline(a), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate800)),
                    if (lead != null)
                      Text(
                        [
                          for (final l in (lead['explanation'] as List? ?? const []))
                            if (!tStr(l).startsWith('Alert levels') && !tStr(l).startsWith('Result')) tStr(l),
                        ].join(' · '),
                        style: const TextStyle(fontSize: 12, color: TColors.slate600),
                      ),
                    if (notes > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('$notes note${notes == 1 ? '' : 's'}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                      ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- one alert

/// The web's AlertDetail side sheet, as a page.
class FlockAlertScreen extends StatefulWidget {
  const FlockAlertScreen({super.key, required this.session, required this.company, required this.alertId, this.onChanged});
  final Session session;
  final Company company;
  final int alertId;
  final VoidCallback? onChanged;

  @override
  State<FlockAlertScreen> createState() => _FlockAlertScreenState();
}

class _FlockAlertScreenState extends State<FlockAlertScreen> {
  late final _api = FlockAlertsApi(widget.session, widget.company);
  Map? _data;
  String? _error;
  final _note = TextEditingController();
  bool _busy = false;
  bool _showEvidence = false;
  Duration _offset = DateTime.now().timeZoneOffset;

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
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await _api.get(widget.alertId);
      if (mounted) setState(() => _data = r is Map ? r : null);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : 'Could not load the alert.');
    }
  }

  Future<void> _act(String kind) async {
    final note = _note.text.trim();
    if ((kind == 'note' || kind == 'resolve') && note.isEmpty) {
      trackerToast(context, kind == 'resolve' ? 'Say what was found or done before resolving.' : 'Write a note first.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      if (kind == 'ack') await _api.acknowledge(widget.alertId, note.isEmpty ? null : note);
      if (kind == 'note') await _api.addNote(widget.alertId, note);
      if (kind == 'resolve') await _api.resolve(widget.alertId, note);
      if (mounted) trackerToast(context, kind == 'ack' ? 'Acknowledged' : (kind == 'note' ? 'Note added' : 'Resolved'));
      _note.clear();
      await _load();
      widget.onChanged?.call();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Not saved', description: e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  String _when(Object? utc) => tStr(utc).isEmpty ? '' : fmtInstant(utc, _offset);

  @override
  Widget build(BuildContext context) {
    final a = _data?['alert'] is Map ? _data!['alert'] as Map : null;
    final events = [for (final e in (_data?['events'] as List? ?? const [])) if (e is Map) e];
    final labels = {for (final s in a == null ? const <Map>[] : alertSignals(a)) tStr(s['signalKey']): tStr(s['label'])};
    const h3 = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TColors.slate900);
    const small = TextStyle(fontSize: 12, color: TColors.slate500);
    return Scaffold(
      appBar: AppBar(title: Text(a != null ? alertFlockLabel(a) : 'Flock alert')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(a != null ? '${formatLongDate(alertDay(a['businessDate']))} — ${alertHeadline(a)}' : ' ',
              style: const TextStyle(fontSize: 13, color: TColors.slate600)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!, style: const TextStyle(fontSize: 13, color: TColors.rose700))),
          if (a == null && _error == null) const Padding(padding: EdgeInsets.only(top: 24), child: LoadingLine('Loading…')),
          if (a != null) ...[
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              severityBadge(a['severity']),
              alertStatusBadge(a['status']),
              if (a['peakSeverity'] != a['severity']) Text('peaked at ${tStr(a['peakSeverity'])}', style: small),
              if (tNum(a['consecutiveDays']) > 1) Text('· ${tNum(a['consecutiveDays']).toInt()} days in a row', style: small),
              InkWell(
                onTap: () => openPoultryHref(context, widget.session, widget.company, '/production-records', label: 'Production records'),
                child: const Text('Production records',
                    style: TextStyle(fontSize: 12, color: TColors.sky700, decoration: TextDecoration.underline)),
              ),
            ]),
            const SizedBox(height: 20),
            const Text('Why it fired', style: h3),
            const SizedBox(height: 12),
            for (final sg in alertSignals(a)) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: sg['isActive'] == true ? Colors.white : TColors.slate50,
                  border: Border.all(color: TColors.slate200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(tStr(sg['label']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate900)),
                    severityBadge(sg['severity'], size: 10),
                    if (sg['isActive'] != true)
                      Text('no longer firing${tStr(sg['clearedAtUtc']).isNotEmpty ? ' since ${_when(sg['clearedAtUtc'])}' : ''}', style: small),
                  ]),
                  const SizedBox(height: 6),
                  for (final line in (sg['explanation'] as List? ?? const []))
                    Text(tStr(line), style: const TextStyle(fontSize: 13, color: TColors.slate700)),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            const Text(
              "Figures come from production records only. Opening-position history (birds lost before tracking began) is never counted, and days with duplicate records or a flock's first recorded day are left out when working out what is normal.",
              style: small,
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: () => setState(() => _showEvidence = !_showEvidence),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_showEvidence ? Icons.expand_less : Icons.expand_more, size: 16, color: TColors.slate600),
                const Text('Structured evidence', style: TextStyle(fontSize: 12, color: TColors.slate600)),
              ]),
            ),
            if (_showEvidence)
              Container(
                margin: const EdgeInsets.only(top: 6),
                constraints: const BoxConstraints(maxHeight: 288),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: TColors.slate900, borderRadius: BorderRadius.circular(6)),
                child: SingleChildScrollView(
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert([for (final x in alertSignals(a)) x['evidence']]),
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: TColors.slate100),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            const Text('Action', style: h3),
            const SizedBox(height: 8),
            AppTextarea(
              controller: _note,
              rows: 3,
              hintText: a['status'] == 'Resolved' ? 'Add a note…' : 'What was checked, found or done…',
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (a['status'] == 'Open' || (a['status'] == 'Cleared' && tStr(a['acknowledgedAtUtc']).isEmpty))
                OutlinedButton(onPressed: _busy ? null : () => _act('ack'), child: const Text('Acknowledge')),
              OutlinedButton(onPressed: _busy ? null : () => _act('note'), child: const Text('Add note')),
              if (a['status'] != 'Resolved') FilledButton(onPressed: _busy ? null : () => _act('resolve'), child: const Text('Resolve')),
            ]),
            const SizedBox(height: 6),
            const Text('Resolving needs a note. Nothing is ever deleted — every step stays in the history below.', style: small),
            const SizedBox(height: 20),
            const Text('History', style: h3),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.only(left: 16),
              decoration: const BoxDecoration(border: Border(left: BorderSide(color: TColors.slate200))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final e in events)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(eventText(e, labels), style: const TextStyle(fontSize: 13, color: TColors.slate800)),
                      if (tStr(e['note']).isNotEmpty) Text('“${tStr(e['note'])}”', style: const TextStyle(fontSize: 13, color: TColors.slate600)),
                      Text('${_when(e['atUtc'])}${tStr(e['actor']).isNotEmpty ? ' · ${tStr(e['actor'])}' : ''}', style: small),
                    ]),
                  ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- daily checks

class _DailyChecks extends StatefulWidget {
  const _DailyChecks({required this.api});
  final FlockAlertsApi api;

  @override
  State<_DailyChecks> createState() => _DailyChecksState();
}

class _DailyChecksState extends State<_DailyChecks> {
  String _date = '';
  List<Map>? _rows;
  String? _error;
  String? _open;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _rows = null;
      _error = null;
    });
    try {
      final r = await widget.api.evaluation(_date);
      if (mounted) setState(() => _rows = rowsOf(r));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : 'Could not load checks.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final byFlock = <int, List<Map>>{};
    for (final r in rows ?? const <Map>[]) {
      byFlock.putIfAbsent(tIntOrNull(r['flockId']) ?? 0, () => []).add(r);
    }
    int worst(List<Map> l) => l.fold<int>(0, (m, r) => tNum(r['severityRank']).toInt() > m ? tNum(r['severityRank']).toInt() : m);
    final flocks = byFlock.values.toList()
      ..sort((x, y) {
        final c = worst(y) - worst(x);
        return c != 0 ? c : tStr(x.first['flockName']).compareTo(tStr(y.first['flockName']));
      });
    final shownDate = rows != null && rows.isNotEmpty && tStr(rows.first['businessDate']).isNotEmpty ? alertDay(rows.first['businessDate']) : _date;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Business date', style: TextStyle(fontSize: 12, color: TColors.slate500)),
      const SizedBox(height: 4),
      SizedBox(
        width: 200,
        child: AppDateField(
          value: DateTime.tryParse(_date),
          hintText: 'Today',
          onChanged: (d) {
            setState(() => _date = d == null ? '' : isoDay(d));
            _load();
          },
        ),
      ),
      const SizedBox(height: 8),
      Text('${shownDate.isNotEmpty ? formatLongDate(shownDate) : 'Today'} — every signal for every flock with a production record, fired or not.',
          style: const TextStyle(fontSize: 13, color: TColors.slate600)),
      const SizedBox(height: 12),
      if (_error != null) TCard(child: Text(_error!, style: const TextStyle(fontSize: 13, color: TColors.rose700))),
      if (rows == null && _error == null) const LoadingLine('Evaluating…'),
      if (rows != null && rows.isEmpty)
        const TCard(
          child: Text('No production records on this date, so there is nothing to check.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate600)),
        ),
      for (final list in flocks) ...[
        TCard(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(alertFlockLabel(list.first), style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
            const SizedBox(height: 6),
            for (var i = 0; i < list.length; i++) _checkRow(list[i], first: i == 0),
          ]),
        ),
        const SizedBox(height: 10),
      ],
    ]);
  }

  Widget _checkRow(Map r, {required bool first}) {
    final key = '${r['flockId']}:${r['signalKey']}';
    final fired = r['status'] == 'Fired';
    final open = _open == key;
    final (bg, border, fg) = fired
        ? (alertSeverityStyle(r['severity']).bg, alertSeverityStyle(r['severity']).border, alertSeverityStyle(r['severity']).fg)
        : r['status'] == 'Normal'
            ? (TColors.emerald50, TColors.emerald200, TColors.emerald700)
            : (TColors.slate50, TColors.slate200, TColors.slate600);
    return Container(
      decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: TColors.slate100))),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => _open = open ? null : key),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(tStr(r['signalLabel']), style: const TextStyle(fontSize: 13, color: TColors.slate700)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(999)),
                  child: Text(fired ? tStr(r['severity']) : evaluationStatusText(r['status']), style: TextStyle(fontSize: 11, color: fg)),
                ),
                Text(
                  '${alertNum(r['currentValue'], 2)} vs ${alertNum(r['baselineMean'], 2)} ${tStr(r['metricUnit'])}'
                  '${r['observed'] != null ? ' · ${alertNum(r['observed'], 2)}${methodUnit(r['method'])}' : ''}',
                  style: const TextStyle(fontSize: 13, color: TColors.slate600),
                ),
              ]),
            ),
            Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: TColors.slate400),
          ]),
        ),
        if (open)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(6)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final l in (r['explanation'] as List? ?? const [])) Text(tStr(l), style: const TextStyle(fontSize: 12, color: TColors.slate700)),
            ]),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- settings

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.api, required this.onSaved});
  final FlockAlertsApi api;
  final VoidCallback onSaved;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  List<Map<String, dynamic>>? _rows;
  String? _saving;

  /// Bumped after each reload so the number boxes take the server's figures.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _reload(firstLoad: true);
  }

  Future<void> _reload({bool firstLoad = false}) async {
    try {
      final r = await widget.api.settings();
      if (mounted) {
        setState(() {
          _rows = [for (final x in rowsOf(r)) Map<String, dynamic>.from(x)];
          _generation += 1;
        });
      }
    } on ApiException catch (e) {
      if (mounted && firstLoad) trackerToast(context, 'Could not load alert settings', description: e.message, error: true);
      if (!firstLoad) rethrow;
    }
  }

  Future<void> _save(Map<String, dynamic> r) async {
    final problem = validateSetting(r);
    if (problem != null) {
      trackerToast(context, 'Not saved', description: problem, error: true);
      return;
    }
    setState(() => _saving = tStr(r['signalKey']));
    try {
      await widget.api.saveSetting(r);
      if (mounted) trackerToast(context, '${tStr(r['label'])} saved');
      await _reload();
      widget.onSaved();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Not saved', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = null);
  }

  Future<void> _reset(Map r) async {
    setState(() => _saving = tStr(r['signalKey']));
    try {
      await widget.api.resetSetting(tStr(r['signalKey']));
      await _reload();
      widget.onSaved();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Not reset', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = null);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: const Text('Alert settings'),
        content: SizedBox(
          width: 640,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text.rich(
              TextSpan(children: [
                t("Each alert compares a flock's figure today with what is "),
                b('normal for that same flock'),
                t(', worked out from its own recent records. Raise the numbers for fewer alerts, lower them for more. Changes apply from the next check; alerts already raised keep the figures they were raised with.'),
              ]),
              style: const TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 16),
            if (_rows == null) const LoadingLine('Loading…'),
            for (final r in _rows ?? const <Map<String, dynamic>>[]) ...[
              _SignalCard(
                key: ValueKey('${r['signalKey']}-$_generation'),
                setting: r,
                saving: _saving == tStr(r['signalKey']),
                onChanged: () => setState(() {}),
                onSave: () => _save(r),
                onReset: () => _reset(r),
              ),
              const SizedBox(height: 16),
            ],
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      );
}

/// One signal's settings card. Edits the map in place, as the web's patch().
class _SignalCard extends StatefulWidget {
  const _SignalCard({super.key, required this.setting, required this.saving, required this.onChanged, required this.onSave, required this.onReset});
  final Map<String, dynamic> setting;
  final bool saving;
  final VoidCallback onChanged, onSave, onReset;

  @override
  State<_SignalCard> createState() => _SignalCardState();
}

class _SignalCardState extends State<_SignalCard> {
  Map<String, dynamic> get r => widget.setting;
  final Map<String, TextEditingController> _c = {};
  bool _advanced = false;

  TextEditingController _ctl(String key) => _c.putIfAbsent(key, () {
        final v = r[key];
        return TextEditingController(text: v == null ? '' : (v is num && v == v.roundToDouble() ? '${v.toInt()}' : '$v'));
      });

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// `num(v)`: "" → null, otherwise the number ([orZero] for required boxes).
  void _set(String key, String v, {num? orElse, bool nullable = false}) {
    final t = v.trim();
    final n = t.isEmpty ? null : num.tryParse(t);
    setState(() => r[key] = nullable ? n : (n ?? orElse ?? 0));
    widget.onChanged();
  }

  Widget _field(String label, String key, {String? help, bool nullable = false, num orElse = 0}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.slate700)),
        const SizedBox(height: 4),
        AppNumberInput(
          key: ValueKey('setting-${r['signalKey']}-$key'),
          controller: _ctl(key),
          allowDecimal: true,
          hintText: '',
          onChanged: (v) => _set(key, v, nullable: nullable, orElse: orElse),
        ),
        if (help != null && help.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(help, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        ],
      ]);

  @override
  Widget build(BuildContext context) {
    final unit = methodUnit(r['method']);
    final hint = methodHint(r['method']);
    final (guardLabel, guardHelp) = guardText(r);
    final example = thresholdExample(r);
    final enabled = r['enabled'] == true;
    final customised = r['isCustomised'] == true;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tStr(r['label']), style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
              Text(
                "Alerts when a flock's ${tStr(r['metricLabel']).toLowerCase()} (${tStr(r['metricUnit'])}) goes ${r['direction'] == 'up' ? 'above' : 'below'} its normal.",
                style: const TextStyle(fontSize: 12, color: TColors.slate500),
              ),
            ]),
          ),
          Switch(
            value: enabled,
            onChanged: (v) {
              setState(() => r['enabled'] = v);
              widget.onChanged();
            },
          ),
          Text(enabled ? 'On' : 'Off', style: const TextStyle(fontSize: 13)),
        ]),
        const SizedBox(height: 12),
        _field('Information ($unit)', 'informationThreshold', help: 'Optional. Leave empty to skip.', nullable: true),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _field('Warning ($unit)', 'warningThreshold')),
          const SizedBox(width: 12),
          Expanded(child: _field('Critical ($unit)', 'criticalThreshold')),
        ]),
        const SizedBox(height: 6),
        Text(thresholdHelp(r), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        if (example != null)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(6)),
            child: Text(example, style: const TextStyle(fontSize: 12, color: TColors.slate700)),
          ),
        if (r['guardField'] != null) ...[
          const SizedBox(height: 12),
          _field(guardLabel, 'guardMinimum', help: guardHelp, nullable: true),
        ],
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0x80F8FAFC),
            border: Border.all(color: TColors.slate100),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            InkWell(
              onTap: () => setState(() => _advanced = !_advanced),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Icon(_advanced ? Icons.expand_less : Icons.expand_more, size: 16, color: TColors.slate600),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text('Advanced — how “normal” is worked out',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.slate600)),
                  ),
                ]),
              ),
            ),
            if (_advanced)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Compare today with normal as', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.slate700)),
                  const SizedBox(height: 4),
                  AppSelect<String>(
                    value: tStr(r['method']),
                    items: [for (final (v, l, _, _) in methodOptions) AppSelectItem(value: v, label: l)],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => r['method'] = v);
                      widget.onChanged();
                    },
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 2),
                    Text(hint, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  ],
                  const SizedBox(height: 12),
                  _field('Work out normal from the last (days)', 'baselineDays',
                      help: "Normal is the flock's average over these days. Today is never included."),
                  const SizedBox(height: 12),
                  _field('Days of records needed first', 'minBaselineDays',
                      help: "A flock with fewer days of records isn't checked yet. This stops false alarms on new flocks."),
                  const SizedBox(height: 12),
                  _field('Treat normal as at least (${tStr(r['metricUnit'])})', 'baselineFloor',
                      help:
                          'Stops silly results when normal is zero or nearly zero. E.g. after weeks with no deaths, 3 deaths would otherwise be “infinity times normal”. Rarely needs changing.'),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: [
          if (customised)
            Text('Customised${tStr(r['updatedBy']).isNotEmpty ? ' by ${tStr(r['updatedBy'])}' : ''}',
                style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          if (customised) TextButton(onPressed: widget.saving ? null : widget.onReset, child: const Text('Reset to default')),
          FilledButton(
            onPressed: widget.saving ? null : widget.onSave,
            child: widget.saving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save'),
          ),
        ]),
      ]),
    );
  }
}
