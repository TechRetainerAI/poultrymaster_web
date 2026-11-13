// Completed setups (migration 416), as the web's
// components/farm-setup/setup-runs-panel.tsx: what each Initial Farm Setup
// created, with Edit / Delete per item and Undo for the whole setup. Undo is
// all or nothing, and the server refuses it while anything has been recorded
// against what the setup created; its reasons show on the card first. Item
// deletes go through the ordinary pages' endpoints, so they keep their guards.
//
// Earlier setups (before 416, migration 417) did not record what they made.
// Their flocks and reconciliations are known; their batches and houses are
// only where those flocks are, so they start unticked and the farm decides.

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../shared/business_dates.dart' show fmtInstant;
import '../../shared/company_clock.dart';
import '../../shared/reason_dialog.dart';
import '../flock_form_screen.dart';
import '../purchase/flock_batches_screen.dart' show FlockBatchEditScreen;
import 'houses_screen.dart';

import 'package:poultrycore_mobile/design/tone.dart';

const _slate400 = Tone.fg(0xFF94A3B8);
const _slate500 = Tone.fg(0xFF64748B);
const _slate600 = Tone.fg(0xFF475569);
const _slate800 = Tone.fg(0xFF1E293B);
const _slate900 = Tone.fg(0xFF0F172A);
const _slate100 = Tone.line(0xFFF1F5F9);
const _slate200 = Tone.line(0xFFE2E8F0);
const _slate50 = Tone.bg(0xFFF8FAFC);
const _rose600 = Tone.fg(0xFFE11D48);
const _rose700 = Tone.fg(0xFFBE123C);
const _amber900 = Tone.fg(0xFF78350F);

const _kinds = {
  'Batch': ('Batches', Icons.inventory_2_outlined),
  'House': ('Houses / pens', Icons.home_outlined),
  'Flock': ('Flocks', Icons.flutter_dash),
  'Reconciliation': ('Batch reconciliations', Icons.balance),
};

int _i(Object? v) => v is num ? v.truncate() : (num.tryParse('${v ?? ''}')?.truncate() ?? 0);
List<Map> _rows(Object? r) {
  final v = r is Map ? (r['data'] ?? r['items']) : r;
  return [for (final x in v is List ? v : const []) if (x is Map) x];
}

List<String> _strings(Object? v) => [for (final x in v is List ? v : const []) '$x'];
String _keyOf(Map i) => '${i['type']}:${_i(i['id'])}';
String _nameOf(Map i) => '${i['name'] ?? ''}'.isNotEmpty ? '${i['name']}' : '#${_i(i['id'])}';

class SetupRunsPanel extends StatefulWidget {
  const SetupRunsPanel({super.key, required this.session, required this.company, this.onChanged});
  final Session session;
  final Company company;
  final VoidCallback? onChanged;
  @override
  State<SetupRunsPanel> createState() => _SetupRunsPanelState();
}

class _SetupRunsPanelState extends State<SetupRunsPanel> {
  List<Map>? _runs;
  String _error = '';
  String? _busy;
  List<Map> _legacy = const [];
  Set<String> _ticked = {};
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  Map<String, String> get _ctx => {'userId': widget.session.tokens.userId ?? '', 'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
  }

  Future<void> _load() async {
    List<Map>? runs;
    var error = '';
    try {
      runs = _rows(await _api.get('/api/PoultryFarmSetup/runs', query: _ctx));
    } on ApiException catch (e) {
      error = e.message.isNotEmpty ? e.message : 'Could not load your completed setups.';
    } catch (_) {
      error = 'Could not load your completed setups.';
    }
    List<Map>? legacy;
    try {
      legacy = _rows(await _api.get('/api/PoultryFarmSetup/legacy', query: _ctx));
    } catch (_) {
      // before 417: no earlier-setups card
    }
    if (!mounted) return;
    setState(() {
      _error = error;
      if (runs != null) _runs = runs;
      if (legacy != null) {
        _legacy = legacy;
        // Suggested (flocks, reconciliations) start ticked unless something blocks them.
        _ticked = {for (final r in legacy) if (r['suggested'] == true && _strings(r['blockers']).isEmpty) _keyOf(r)};
      }
    });
  }

  void _toast(String title, [String? description, bool error = false]) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      backgroundColor: error ? Tone.button(const Tone.bg(0xFFBE123C)) : null,
      content: Text(description == null || description.isEmpty ? title : '$title — $description'),
    ));
  }

  void _toggle(Map c, bool on) => setState(() {
        void apply(String k) => on ? _ticked.add(k) : _ticked.remove(k);
        apply(_keyOf(c));
        // A batch takes its setup reconciliations with it.
        if (c['type'] == 'Batch') {
          for (final r in _legacy) {
            if (r['type'] == 'Reconciliation' && _i(r['batchid']) == _i(c['id'])) apply(_keyOf(r));
          }
        }
      });

  Future<void> _edit(Map item) async {
    final id = _i(item['id']);
    Widget? screen;
    switch (item['type']) {
      case 'Batch':
        screen = FlockBatchEditScreen(session: widget.session, company: widget.company, batchId: id);
      case 'Flock':
        try {
          final r = await _api.get('/api/Flock/$id', query: _ctx);
          final row = r is Map && r['data'] is Map ? r['data'] as Map : r;
          if (row is Map) screen = FlockFormScreen(session: widget.session, company: widget.company, existing: Map<String, dynamic>.from(row));
        } on ApiException catch (e) {
          _toast('Could not open the flock', e.message, true);
        }
      case 'House':
        screen = HousesScreen(session: widget.session, company: widget.company);
    }
    if (screen == null || !mounted) return;
    final s = screen;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => s));
    if (mounted) _load();
  }

  Future<void> _remove(String scope, Map item) async {
    final type = '${item['type']}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${type.toLowerCase()}?'),
        content: Text('Delete ${type.toLowerCase()} "${item['name'] ?? item['id']}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Tone.button(const Tone.bg(0xFFE11D48))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final id = _i(item['id']);
    setState(() => _busy = '$scope:$type:$id');
    final path = switch (type) {
      'Flock' => '/api/Flock/$id',
      'Batch' => '/api/MainFlockBatch/$id',
      _ => '/api/House/$id',
    };
    try {
      final res = await _api.delete(path, query: _ctx);
      if (res is Map && res['deleted'] == false) throw ApiException(0, '${res['message'] ?? 'Not deleted.'}');
      if (!mounted) return;
      setState(() => _busy = null);
      _toast('${item['name'] ?? type} deleted');
      await _load();
      widget.onChanged?.call();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      _toast('Not deleted', e.message, true);
    }
  }

  Future<void> _undoRun(Map run) async {
    final id = _i(run['setuprunid']);
    final live = [for (final i in (run['items'] is List ? run['items'] as List : const [])) if (i is Map && i['gone'] != true) i].length;
    final reason = await showReasonDialog(
      context,
      title: 'Undo setup #$id?',
      description: 'This removes everything this setup created: $live item(s) — its flocks, batches, houses and batch reconciliations. '
          'It cannot be redone; you would run the setup again.\n\nWhy is it being undone?',
      confirmLabel: 'Undo setup',
      destructive: true,
    );
    if (reason == null || reason.trim().isEmpty || !mounted) return;
    setState(() => _busy = 'undo:$id');
    try {
      await _api.post('/api/PoultryFarmSetup/runs/$id/reverse',
          body: {'UserId': _ctx['userId'], 'FarmId': _ctx['farmId'], 'Reason': reason.trim()});
      if (!mounted) return;
      setState(() => _busy = null);
      _toast('Setup undone', 'Everything it created has been removed.');
      await _load();
      widget.onChanged?.call();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      _toast('Setup not undone', e.message, true);
    }
  }

  Future<void> _undoLegacy() async {
    final items = [for (final c in _legacy) if (_ticked.contains(_keyOf(c))) c];
    if (items.isEmpty) return;
    final reason = await showReasonDialog(
      context,
      title: 'Undo ${items.length} ticked item(s)?',
      description: 'Removes exactly what you ticked from the earlier setup: ${items.map(_nameOf).join(', ')}. '
          'It is refused, and nothing changes, if a ticked batch or house still holds a flock you did not tick.\n\nWhy is it being undone?',
      confirmLabel: 'Undo',
      destructive: true,
    );
    if (reason == null || reason.trim().isEmpty || !mounted) return;
    setState(() => _busy = 'undo:legacy');
    try {
      await _api.post('/api/PoultryFarmSetup/legacy/reverse', body: {
        'UserId': _ctx['userId'],
        'FarmId': _ctx['farmId'],
        'Reason': reason.trim(),
        'Items': [for (final c in items) {'Type': c['type'], 'Id': _i(c['id'])}],
      });
      if (!mounted) return;
      setState(() => _busy = null);
      _toast('Undone', '${items.length} item(s) from the earlier setup were removed.');
      await _load();
      widget.onChanged?.call();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      _toast('Not undone', e.message, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error.isNotEmpty) return Text(_error, style: const TextStyle(fontSize: 14, color: _rose700));
    final runs = _runs;
    if (runs == null) {
      return const Row(children: [
        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 8),
        Text('Loading completed setups…', style: TextStyle(fontSize: 14, color: _slate500)),
      ]);
    }
    if (runs.isEmpty && _legacy.isEmpty) return const SizedBox.shrink();
    return Column(key: const ValueKey('setup-runs-panel'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Completed setups', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _slate900)),
      const Text('What each setup created. Edit or delete single items, or undo a whole setup while nothing has been recorded against it.',
          style: TextStyle(fontSize: 14, color: _slate600)),
      for (final run in runs) ...[const SizedBox(height: 12), _runCard(run)],
      if (_legacy.isNotEmpty) ...[const SizedBox(height: 12), _legacyCard()],
    ]);
  }

  Widget _card({required Key key, required Widget header, Widget? banner, required List<Widget> groups, Widget? footer, double opacity = 1}) => Opacity(
        key: key,
        opacity: opacity,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: _slate50,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: header,
            ),
            ?banner,
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (i, g) in groups.indexed) ...[if (i > 0) const SizedBox(height: 14), g],
              ]),
            ),
            ?footer,
          ]),
        ),
      );

  Widget _banner(String text) => Container(
        color: const Tone.bg(0xFFFFFBEB),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(text, style: const TextStyle(fontSize: 12, color: _amber900)),
      );

  Widget _group(String type, List<Widget> rows) {
    final (label, icon) = _kinds[type]!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(icon, size: 14, color: _slate500),
        const SizedBox(width: 6),
        Text('${label.toUpperCase()} (${rows.length})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: .4, color: _slate500)),
      ]),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(border: Border.all(color: _slate100), borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          for (final (i, r) in rows.indexed)
            Container(
              decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: _slate100))),
              child: r,
            ),
        ]),
      ),
    ]);
  }

  Widget _iconButton(String tip, IconData icon, VoidCallback? onTap, {Color? color, bool busy = false, Key? key}) => IconButton(
        key: key,
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
        onPressed: onTap,
        icon: busy
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon, size: 16, color: onTap == null ? const Tone.fg(0xFFCBD5E1) : color),
      );

  Widget _runCard(Map run) {
    final id = _i(run['setuprunid']);
    final reversed = run['status'] == 'Reversed';
    final items = [for (final i in (run['items'] is List ? run['items'] as List : const [])) if (i is Map) i];
    final liveFlocks = items.any((i) => i['type'] == 'Flock' && i['gone'] != true);
    final blockers = _strings(run['blockers']);
    final day = '${run['businessdate'] ?? ''}';
    final groups = [
      for (final t in _kinds.keys)
        if (items.any((i) => i['type'] == t))
          _group(t, [
            for (final item in items.where((i) => i['type'] == t))
              () {
                final key = '$id:${item['type']}:${_i(item['id'])}';
                final itemBlockers = _strings(item['blockers']);
                // A batch's flocks go first, or they would be left pointing at nothing.
                final blocked = itemBlockers.isNotEmpty || (item['type'] == 'Batch' && liveFlocks);
                final why = itemBlockers.isNotEmpty ? itemBlockers.join('; ') : item['type'] == 'Batch' && liveFlocks ? "Delete this setup's flocks first." : '';
                final gone = item['gone'] == true;
                return Padding(
                  key: ValueKey('run-item-$key'),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Row(children: [
                    Expanded(
                      child: Text(_nameOf(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: gone ? _slate400 : _slate800, decoration: gone ? TextDecoration.lineThrough : null)),
                    ),
                    if (gone)
                      Text(item['type'] == 'Reconciliation' ? 'Reversed' : 'Deleted', style: const TextStyle(fontSize: 11, color: _slate400))
                    else if (!reversed && item['type'] != 'Reconciliation') ...[
                      _iconButton('Edit', Icons.edit_outlined, _busy != null ? null : () => _edit(item)),
                      _iconButton(blocked ? 'Cannot delete: $why' : 'Delete', Icons.delete_outline,
                          blocked || _busy != null ? null : () => _remove('$id', item),
                          color: _rose600, busy: _busy == key, key: ValueKey('run-delete-$key')),
                    ],
                  ]),
                );
              }(),
          ]),
    ];
    return _card(
      key: ValueKey('setup-run-$id'),
      opacity: reversed ? .75 : 1,
      header: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Setup #$id${day.isNotEmpty ? ' · ${day.length >= 10 ? day.substring(0, 10) : day}' : ''}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _slate900)),
          Text(
            'Completed ${fmtInstant(run['completedat'], _offset)}'
            '${reversed && run['reversedat'] != null ? ' · undone ${fmtInstant(run['reversedat'], _offset)}${'${run['reversalreason'] ?? ''}'.isNotEmpty ? ' (${run['reversalreason']})' : ''}' : ''}',
            style: const TextStyle(fontSize: 12, color: _slate500),
          ),
        ]),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: reversed ? const Tone.bg(0xFFE2E8F0) : const Tone.bg(0xFFD1FAE5),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(reversed ? 'Undone' : 'Completed',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: reversed ? const Tone.fg(0xFF334155) : const Tone.fg(0xFF065F46))),
        ),
        if (!reversed)
          Tooltip(
            message: blockers.isNotEmpty ? 'Cannot undo: ${blockers.join('; ')}' : 'Remove everything this setup created',
            child: OutlinedButton.icon(
              key: ValueKey('undo-run-$id'),
              style: OutlinedButton.styleFrom(
                backgroundColor: Tone.button(Tone.bg(0xFFFFFFFF)),
                foregroundColor: _rose700,
                side: const BorderSide(color: Tone.line(0xFFFECDD3)),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: blockers.isNotEmpty || _busy != null ? null : () => _undoRun(run),
              icon: _busy == 'undo:$id'
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.undo, size: 16),
              label: const Text('Undo setup'),
            ),
          ),
      ]),
      banner: !reversed && blockers.isNotEmpty ? _banner('Cannot be undone while things are recorded against it: ${blockers.join('; ')}.') : null,
      groups: groups,
    );
  }

  Widget _legacyCard() {
    final groups = [
      for (final t in _kinds.keys)
        if (_legacy.any((c) => c['type'] == t))
          _group(t, [
            for (final c in _legacy.where((c) => c['type'] == t))
              () {
                final k = _keyOf(c);
                final blockers = _strings(c['blockers']);
                final blocked = blockers.isNotEmpty;
                final row = Padding(
                  key: ValueKey('legacy-$k'),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(children: [
                    Checkbox(
                      key: ValueKey('legacy-tick-$k'),
                      value: _ticked.contains(k),
                      visualDensity: VisualDensity.compact,
                      onChanged: blocked || _busy != null ? null : (v) => _toggle(c, v == true),
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: _nameOf(c)),
                          if (c['suggested'] != true)
                            const TextSpan(text: '  MAYBE OLDER', style: TextStyle(fontSize: 10, color: Tone.fg(0xFFD97706))),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: blocked ? _slate400 : _slate800),
                      ),
                    ),
                    if (c['type'] != 'Reconciliation') ...[
                      _iconButton('Edit', Icons.edit_outlined, _busy != null ? null : () => _edit(c)),
                      _iconButton(
                        c['type'] != 'Flock' && blocked ? 'Cannot delete: ${blockers.join('; ')}' : 'Delete',
                        Icons.delete_outline,
                        _busy != null || (c['type'] != 'Flock' && blocked) ? null : () => _remove('legacy', c),
                        color: _rose600,
                        busy: _busy == 'legacy:${c['type']}:${_i(c['id'])}',
                      ),
                    ],
                  ]),
                );
                return blocked ? Tooltip(message: 'Cannot be undone: ${blockers.join('; ')}', child: row) : row;
              }(),
          ]),
    ];
    return _card(
      key: const ValueKey('setup-runs-legacy'),
      header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Earlier setups', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _slate900)),
        const Text(
          'Completed before setups recorded what they created. Flocks and reconciliations below came from a setup. '
          'Batches and houses are where those flocks are and may be older — tick them only if the setup created them.',
          style: TextStyle(fontSize: 12, color: _slate500),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('undo-legacy'),
            style: OutlinedButton.styleFrom(
              backgroundColor: Tone.button(Tone.bg(0xFFFFFFFF)),
              foregroundColor: _rose700,
              side: const BorderSide(color: Tone.line(0xFFFECDD3)),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: _ticked.isEmpty || _busy != null ? null : _undoLegacy,
            icon: const Icon(Icons.undo, size: 16),
            label: Text('Undo ticked (${_ticked.length})'),
          ),
        ),
      ]),
      groups: groups,
      footer: _legacy.any((c) => _strings(c['blockers']).isNotEmpty)
          ? _banner('Greyed-out items have records against them (press and hold for the reasons) and cannot be undone.')
          : null,
    );
  }
}
