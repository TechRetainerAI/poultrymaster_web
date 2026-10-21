import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';
import '../shared/iam_permissions.dart';
import 'flock_closeout_screen.dart' show FlockLifetimeScreen;
import 'flock_lifecycle_logic.dart';
import 'poultry_links.dart';
import 'sales/balances_logic.dart' show pageSlice;
import 'sales/balances_widgets.dart';
import 'trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import 'trackers/tracker_widgets.dart';
import '../shared/reason_select.dart';

/// Poultry → Tools → Flock Lifecycle, as `app/poultry-lifecycle/page.tsx`
/// (migration 347): reminders for the milestones the FARM defines, worked out
/// from each flock's age. Three tabs — Tasks, Plans, Assignments.

const lifecycleViewKey = 'poultry.lifecycle.view';
const lifecycleCreateKey = 'poultry.lifecycle.create';
const lifecycleEditKey = 'poultry.lifecycle.edit';
const lifecycleDeleteKey = 'poultry.lifecycle.delete';

const _indigo600 = Color(0xFF4F46E5);
const _indigo500 = Color(0xFF6366F1);
const _indigo50 = Color(0xFFEEF2FF);
const _blue700 = Color(0xFF1D4ED8);

String _day(Object? v) {
  final s = tStr(v);
  return s.isEmpty ? '—' : (s.length >= 10 ? s.substring(0, 10) : s);
}

/// The Lifecycle API (PoultryLifecycleController). farmId in the query on
/// every call, and in the body of every write.
class LifecycleApi {
  LifecycleApi(this.session, this.company);
  final Session session;
  final Company company;
  ApiClient get _c => session.farmClient;
  String get farmId => company.farmId;
  static const base = '/api/Poultry/lifecycle';

  Future<Object?> tasks(String view, int? flockId) =>
      _c.get('$base/tasks', query: {'farmId': farmId, 'view': view, if (flockId != null) 'flockId': '$flockId'});
  Future<Object?> summary() => _c.get('$base/summary', query: {'farmId': farmId});
  Future<Object?> history(int flockId, int milestoneId) =>
      _c.get('$base/tasks/history', query: {'farmId': farmId, 'flockId': '$flockId', 'milestoneId': '$milestoneId'});
  Future<Object?> setStatus(int flockId, int milestoneId, String status, String? note) => _c.put('$base/tasks/status',
      query: {'farmId': farmId},
      body: {'flockId': flockId, 'milestoneId': milestoneId, 'status': status, 'note': note, 'farmId': farmId});
  Future<Object?> templates() => _c.get('$base/templates', query: {'farmId': farmId});
  Future<Object?> template(int id) => _c.get('$base/templates/$id', query: {'farmId': farmId});
  Future<Object?> createTemplate(Map<String, dynamic> input) =>
      _c.post('$base/templates', query: {'farmId': farmId}, body: {...input, 'farmId': farmId});
  Future<Object?> updateTemplate(int id, Map<String, dynamic> input) =>
      _c.put('$base/templates/$id', query: {'farmId': farmId}, body: {...input, 'farmId': farmId});
  Future<Object?> deleteTemplate(int id) => _c.delete('$base/templates/$id', query: {'farmId': farmId});
  Future<Object?> assignments() => _c.get('$base/assignments', query: {'farmId': farmId});
  Future<Object?> assign(Map<String, dynamic> input) =>
      _c.post('$base/assignments', query: {'farmId': farmId}, body: {...input, 'farmId': farmId});
  Future<Object?> removeAssignment(int id) => _c.delete('$base/assignments/$id', query: {'farmId': farmId});
}

class FlockLifecycleScreen extends StatefulWidget {
  const FlockLifecycleScreen({super.key, required this.session, required this.company, this.initialTab, this.initialFlockId});
  final Session session;
  final Company company;

  /// `?tab=` and `?flockId=`, as the web reads them.
  final String? initialTab;
  final String? initialFlockId;

  @override
  State<FlockLifecycleScreen> createState() => _FlockLifecycleScreenState();
}

class _FlockLifecycleScreenState extends State<FlockLifecycleScreen> {
  late final _api = LifecycleApi(widget.session, widget.company);
  late String _tab = const ['tasks', 'plans', 'assignments'].contains(widget.initialTab) ? widget.initialTab! : 'tasks';
  String _view = 'Open';
  late String _flockFilter = widget.initialFlockId ?? 'all';
  List<Map> _tasks = [], _templates = [], _assignments = [], _flocks = [], _batches = [];
  Map? _summary;
  bool _loading = true;
  String? _busyKey;
  bool _permsLoaded = false;
  Set<String> _held = {};
  int _page = 1, _pageSize = 10;
  Duration _offset = DateTime.now().timeZoneOffset;

  bool get _canView => !_permsLoaded || _held.contains(lifecycleViewKey);
  bool get _canCreate => _held.contains(lifecycleCreateKey);
  bool get _canEdit => _held.contains(lifecycleEditKey);
  bool get _canDelete => _held.contains(lifecycleDeleteKey);

  @override
  void initState() {
    super.initState();
    canDoAll(widget.session, widget.company, const [lifecycleViewKey, lifecycleCreateKey, lifecycleEditKey, lifecycleDeleteKey])
        .then((h) {
      if (mounted) {
        setState(() {
          _held = h;
          _permsLoaded = true;
        });
      }
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _loadAll();
  }

  void _toast(String title, {String? description, bool error = false}) {
    if (mounted) trackerToast(context, title, description: description, error: error);
  }

  Future<void> _loadTasks() async {
    try {
      final r = await Future.wait([
        _api.tasks(_view, _flockFilter == 'all' ? null : int.tryParse(_flockFilter)),
        _api.summary(),
      ]);
      if (!mounted) return;
      setState(() {
        _tasks = sortTasks(rowsOf(r[0]));
        _summary = r[1] is Map ? r[1] as Map : null;
        _page = 1;
      });
    } on ApiException catch (e) {
      _toast('Could not load lifecycle tasks', description: e.message, error: true);
    }
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final uq = {'userId': widget.session.tokens.userId ?? '', 'farmId': widget.company.farmId};
    Future<Object?> soft(String path) async {
      try {
        return await widget.session.farmClient.get(path, query: uq);
      } on ApiException {
        return const [];
      }
    }

    try {
      final r = await Future.wait([_api.templates(), _api.assignments(), soft('/api/Flock'), soft('/api/MainFlockBatch')]);
      if (mounted) {
        setState(() {
          _templates = rowsOf(r[0]);
          _assignments = rowsOf(r[1]);
          _flocks = rowsOf(r[2]);
          _batches = rowsOf(r[3]);
        });
      }
      await _loadTasks();
    } on ApiException catch (e) {
      _toast('Could not load the lifecycle assistant', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map> get _openFlocks {
    final out = [for (final f in _flocks) if (tStr(f['closedDate']).isEmpty) f];
    out.sort((a, b) => tStr(a['name']).compareTo(tStr(b['name'])));
    return out;
  }

  List<Map> get _activeTemplates => [for (final t in _templates) if (t['isActive'] == true) t];

  String _key(Map t) => '${t['flockId']}-${t['milestoneId']}';

  Future<void> _complete(Map t) async {
    setState(() => _busyKey = _key(t));
    try {
      await _api.setStatus(tIntOrNull(t['flockId']) ?? 0, tIntOrNull(t['milestoneId']) ?? 0, 'Completed', null);
      _toast('Marked complete', description: '${tStr(t['title'])} — ${tStr(t['flockName'])}');
      await _loadTasks();
    } on ApiException catch (e) {
      _toast('Could not complete the task', description: e.message, error: true);
    }
    if (mounted) setState(() => _busyKey = null);
  }

  Future<void> _skip(Map t) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => LifecyclePromptDialog(
        title: 'Skip "${tStr(t['title'])}"?',
        description: "${tStr(t['flockName'])}. The reason is kept in the task's history.",
        label: 'Why is it being skipped?',
        options: skipReasons,
        confirmLabel: 'Skip task',
        onSubmit: (note) async {
          try {
            await _api.setStatus(tIntOrNull(t['flockId']) ?? 0, tIntOrNull(t['milestoneId']) ?? 0, 'Skipped', note);
          } on ApiException catch (e) {
            _toast('Could not skip the task', description: e.message, error: true);
            rethrow;
          }
        },
      ),
    );
    if (done == true) {
      _toast('Task skipped');
      await _loadTasks();
    }
  }

  Future<void> _reopen(Map t) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => LifecyclePromptDialog(
        title: 'Reopen "${tStr(t['title'])}"?',
        description: 'It goes back to the list with its current status. The earlier completion stays in the history.',
        label: 'Note (optional)',
        allowEmpty: true,
        options: taskReopenReasons,
        confirmLabel: 'Reopen',
        onSubmit: (note) async {
          try {
            await _api.setStatus(tIntOrNull(t['flockId']) ?? 0, tIntOrNull(t['milestoneId']) ?? 0, 'Open', note.isEmpty ? null : note);
          } on ApiException catch (e) {
            _toast('Could not reopen the task', description: e.message, error: true);
            rethrow;
          }
        },
      ),
    );
    if (done == true) {
      _toast('Task reopened');
      await _loadTasks();
    }
  }

  void _history(Map t) => showDialog<void>(
        context: context,
        builder: (_) => _HistoryDialog(api: _api, task: t, offset: _offset),
      );

  void _openAction(Map t) {
    final href = lifecycleActionHref(t);
    if (href == null) return;
    final label = lifecycleActionLabel(t['actionType']) ?? '';
    if (href.startsWith('/flock-closeout/')) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FlockLifetimeScreen(session: widget.session, company: widget.company, flockId: tIntOrNull(t['flockId']) ?? 0),
      ));
      return;
    }
    openPoultryHref(context, widget.session, widget.company, href, label: label);
  }

  Future<void> _editPlan(Map? template) async {
    Map? full = template;
    if (template != null) {
      try {
        final r = await _api.template(tIntOrNull(template['templateId']) ?? 0);
        full = r is Map ? r : template;
      } on ApiException catch (e) {
        _toast('Could not open the plan', description: e.message, error: true);
        return;
      }
    }
    if (!mounted) return;
    final saved = await showDialog<bool>(context: context, builder: (_) => _PlanEditorDialog(api: _api, template: full, toast: _toast));
    if (saved == true) await _loadAll();
  }

  Future<void> _deletePlan(Map t) async {
    final ok = await confirmDelete(context,
        title: 'Delete "${tStr(t['name'])}"?',
        description: 'A plan with task history is retired (made inactive) instead of deleted, so its history stays readable.');
    if (!ok) return;
    try {
      final r = await _api.deleteTemplate(tIntOrNull(t['templateId']) ?? 0);
      _toast(r is Map && r['outcome'] == 'Retired' ? 'Plan retired (it has history)' : 'Plan deleted');
      await _loadAll();
    } on ApiException catch (e) {
      _toast('Could not delete the plan', description: e.message, error: true);
    }
  }

  Future<void> _removeAssignment(Map a) async {
    final isBatch = a['batchId'] != null;
    final count = tNum(a['flockCount']).toInt();
    final ok = await confirmDelete(context,
        title: 'Remove "${tStr(a['templateName'])}" from ${isBatch ? 'batch ${tStr(a['batchCode'])}'.trim() : 'flock ${tStr(a['flockName'])}'.trim()}?',
        description: '${isBatch ? "Its $count open flock${count == 1 ? '' : 's'} will stop getting these reminders, unless a flock has its own plan." : "This flock will go back to its batch's plan, or get no reminders if the batch has none."}'
            '\n\nCompleted and skipped tasks and their history are kept. Assigning the plan again brings the reminders back.',
        confirmLabel: 'Remove');
    if (!ok) return;
    try {
      await _api.removeAssignment(tIntOrNull(a['assignmentId']) ?? 0);
      _toast('Assignment removed');
      await _loadAll();
    } on ApiException catch (e) {
      _toast('Could not remove it', description: e.message, error: true);
    }
  }

  Future<void> _assign() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AssignDialog(api: _api, templates: _activeTemplates, batches: _batches, flocks: _openFlocks, toast: _toast),
    );
    if (saved == true) await _loadAll();
  }

  void _showView(String view) {
    setState(() {
      _tab = 'tasks';
      _view = view;
    });
    _loadTasks();
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-lifecycle');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Flock Lifecycle')),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: !_canView
              ? [
                  TCard(
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Column(children: [
                        Icon(Icons.lock_outline, size: 24, color: TColors.slate400),
                        SizedBox(height: 8),
                        Text('You do not have access to the Flock Lifecycle assistant.',
                            textAlign: TextAlign.center, style: TextStyle(color: TColors.slate600)),
                      ]),
                    ),
                  ),
                ]
              : [
                  Row(children: [
                    const Icon(Icons.event_note_outlined, size: 22, color: _indigo600),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Flock Lifecycle', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900)),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _loadAll,
                      icon: _loading
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh, size: 16),
                      label: const Text('Refresh'),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(children: [
                      t('Reminders for the milestones '),
                      b('your farm'),
                      t(" defines — housing moves, reviews, treatments your vet prescribes — worked out from each flock's age. VisibilityCore does not recommend any schedule; it only reminds you of the one you write."),
                    ]),
                    style: const TextStyle(fontSize: 13, color: TColors.slate600),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(builder: (context, c) {
                    final half = (c.maxWidth - 12) / 2;
                    final s = _summary;
                    return Wrap(spacing: 12, runSpacing: 12, children: [
                      SizedBox(width: half, child: _tile('Overdue', s?['overdue'], TColors.rose100, const Color(0xFFFDA4AF), TColors.rose800, () => _showView('Overdue'))),
                      SizedBox(width: half, child: _tile('Due now', s?['due'], TColors.amber100, TColors.amber300, TColors.amber800, () => _showView('Due'))),
                      SizedBox(width: half, child: _tile('Coming up', s?['upcoming'], TColors.blue100, TColors.blue300, const Color(0xFF1E40AF), () => _showView('Upcoming'))),
                      SizedBox(
                          width: half,
                          child: _tile('Completed (30 days)', s?['completedLast30'], TColors.emerald100, TColors.emerald300, TColors.emerald800,
                              () => _showView('Completed'))),
                    ]);
                  }),
                  const SizedBox(height: 14),
                  _tabsList(),
                  const SizedBox(height: 12),
                  if (_tab == 'tasks') ..._tasksTab(),
                  if (_tab == 'plans') ..._plansTab(),
                  if (_tab == 'assignments') ..._assignmentsTab(),
                ],
        ),
      ),
    );
  }

  Widget _tile(String label, Object? value, Color bg, Color border, Color fg, VoidCallback onTap) => Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 12, color: fg)),
              Text(value == null ? '—' : '${tNum(value).toInt()}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: fg)),
            ]),
          ),
        ),
      );

  /// tabListCls / tabTriggerCls / tabCountCls: a white bordered strip, the
  /// active trigger blue-600 with a white count.
  Widget _tabsList() {
    final s = _summary;
    final dueCount = s == null ? 0 : tNum(s['overdue']).toInt() + tNum(s['due']).toInt();
    final tabs = [
      ('tasks', Icons.checklist, 'Tasks', dueCount > 0 ? '$dueCount' : null),
      ('plans', Icons.assignment_outlined, 'Plans', '${_activeTemplates.length}'),
      ('assignments', Icons.link, 'Assignments', '${_assignments.length}'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final (v, icon, label, count) in tabs) ...[
            if (v != 'tasks') const SizedBox(width: 4),
            Material(
              color: _tab == v ? TColors.blue600 : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _tab = v),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 16, color: _tab == v ? Colors.white : TColors.slate600),
                    const SizedBox(width: 6),
                    Text(label,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _tab == v ? Colors.white : TColors.slate600)),
                    if (count != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: _tab == v ? Colors.white.withValues(alpha: .2) : TColors.slate100,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(count,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _tab == v ? Colors.white : TColors.slate600)),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _emptyCard(List<Widget> children) => TCard(
        padding: const EdgeInsets.all(24),
        child: Center(child: Column(children: children)),
      );

  Widget _statusBadge(Object? status) {
    final (bg, fg, border) = lifecycleStatusTone(status);
    return TBadge(tStr(status), bg: bg, fg: fg, border: border);
  }

  // ---------------------------------------------------------------- tasks

  List<Widget> _tasksTab() {
    final open = _openFlocks;
    final flockItems = [
      const AppSelectItem(value: 'all', label: 'All flocks'),
      for (final f in open)
        AppSelectItem(
          value: tStr(f['flockId']),
          label: '${tStr(f['name'])}${tStr(f['batchName']).isNotEmpty ? ' · ${tStr(f['batchName'])}' : ''}',
        ),
    ];
    final estimated = _tasks.any((t) => t['isEstimated'] == true);
    final pageRows = pageSlice(_tasks, _page, _pageSize);
    return [
      AppSelect<String>(
        value: _view,
        items: [for (final (v, l) in lifecycleViews) AppSelectItem(value: v, label: l)],
        onChanged: (v) {
          if (v == null) return;
          setState(() => _view = v);
          _loadTasks();
        },
      ),
      const SizedBox(height: 8),
      AppSelect<String>(
        value: flockItems.any((i) => i.value == _flockFilter) ? _flockFilter : null,
        hintText: 'All flocks',
        items: flockItems,
        onChanged: (v) {
          if (v == null) return;
          setState(() => _flockFilter = v);
          _loadTasks();
        },
      ),
      const SizedBox(height: 12),
      if (estimated) ...[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: TColors.amber200), borderRadius: BorderRadius.circular(6)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.warning_amber_rounded, size: 16, color: TColors.amber900),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  t('Dates marked '),
                  b('Estimated'),
                  t(" come from a flock whose start date was worked out from an age entered during farm setup."),
                ]),
                style: const TextStyle(fontSize: 13, color: TColors.amber900),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
      ],
      if (_loading)
        const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading…'))
      else if (_tasks.isEmpty)
        _emptyCard(_assignments.isEmpty
            ? [
                const Text('No flock follows a lifecycle plan yet.', style: TextStyle(color: TColors.slate500)),
                const SizedBox(height: 8),
                Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  const Text('Write a plan on the ', style: TextStyle(fontSize: 13, color: TColors.slate500)),
                  InkWell(
                    onTap: () => setState(() => _tab = 'plans'),
                    child: const Text('Plans',
                        style: TextStyle(fontSize: 13, color: _blue700, decoration: TextDecoration.underline)),
                  ),
                  const Text(' tab, then assign it to a batch.', style: TextStyle(fontSize: 13, color: TColors.slate500)),
                ]),
              ]
            : [const Text("Nothing here — you're up to date.", style: TextStyle(color: TColors.slate500))])
      else ...[
        for (final task in pageRows) ...[_taskCard(task), const SizedBox(height: 8)],
        CompactPager(
          total: _tasks.length,
          page: _page,
          pageSize: _pageSize,
          onPage: (p) => setState(() => _page = p),
          onPageSize: (s) => setState(() {
            _pageSize = s;
            _page = 1;
          }),
        ),
      ],
    ];
  }

  Widget _taskCard(Map task) {
    final key = _key(task);
    final href = lifecycleActionHref(task);
    final status = tStr(task['status']);
    final done = status == 'Completed' || status == 'Skipped';
    final busy = _busyKey == key;
    const meta = TextStyle(fontSize: 12, color: TColors.slate500);
    final via = tStr(task['assignedVia']) == 'Batch' ? ' (via batch ${tStr(task['batchCode'])})' : '';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, runSpacing: 6, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(tStr(task['title']), style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
            Text(taskSentence(task), style: const TextStyle(fontSize: 13, color: TColors.slate600)),
          ]),
          Wrap(spacing: 6, children: [
            _statusBadge(status),
            if (task['isEstimated'] == true) const TBadge('Estimated', bg: TColors.amber50, fg: TColors.amber800, border: TColors.amber300),
          ]),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 16, runSpacing: 4, children: [
          Text(
              '${milestoneAgeLabel(task['ageUnit'], task['ageValue'])} · due ${_day(task['dueDate'])}${tStr(task['ageUnit']) == 'Week' ? '–${_day(task['dueWindowEnd'])}' : ''}',
              style: meta),
          Text(dueLabel(task), style: meta),
          Text('Flock age ${formatAgeDays(tNum(task['currentAgeDays']))}', style: meta),
          Text('${tStr(task['templateName'])}$via', style: meta),
          if (tStr(task['category']).isNotEmpty) Text(tStr(task['category']), style: meta),
        ]),
        if (tStr(task['description']).isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(tStr(task['description']), style: const TextStyle(fontSize: 13, color: TColors.slate700)),
        ],
        if (done) ...[
          const SizedBox(height: 8),
          Text(
            '$status ${tStr(task['actedAt']).isNotEmpty ? fmtInstant(task['actedAt'], _offset) : ''}'
            '${tStr(task['actedBy']).isNotEmpty ? ' by ${tStr(task['actedBy'])}' : ''}'
            '${tStr(task['note']).isNotEmpty ? ' — ${tStr(task['note'])}' : ''}',
            style: meta,
          ),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (href != null)
            OutlinedButton.icon(
              onPressed: () => _openAction(task),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(lifecycleActionLabel(task['actionType']) ?? ''),
            ),
          if (_canEdit && !done && status != 'Scheduled') ...[
            FilledButton.icon(
              onPressed: busy ? null : () => _complete(task),
              icon: busy
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_outline, size: 16),
              label: Text(busy ? '' : 'Complete'),
            ),
            OutlinedButton.icon(
              onPressed: () => _skip(task),
              icon: const Icon(Icons.skip_next_outlined, size: 16),
              label: const Text('Skip'),
            ),
          ],
          if (_canEdit && done)
            OutlinedButton.icon(
              onPressed: () => _reopen(task),
              icon: const Icon(Icons.restart_alt, size: 16),
              label: const Text('Reopen'),
            ),
          if (task['taskId'] != null)
            TextButton.icon(
              onPressed: () => _history(task),
              icon: const Icon(Icons.history, size: 16),
              label: const Text('History'),
            ),
        ]),
      ]),
    );
  }

  // ---------------------------------------------------------------- plans

  List<Widget> _plansTab() => [
        Row(children: [
          const Expanded(
            child: Text('Each plan is a list of milestones at ages your farm chooses.', style: TextStyle(fontSize: 13, color: TColors.slate600)),
          ),
          if (_canCreate) ...[
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: () => _editPlan(null), icon: const Icon(Icons.add, size: 16), label: const Text('New plan')),
          ],
        ]),
        const SizedBox(height: 12),
        if (_templates.isEmpty)
          _emptyCard(const [
            Text('No plans yet. Plans are written by your farm — none are built in.',
                textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
          ])
        else
          for (final p in _templates) ...[_planCard(p), const SizedBox(height: 12)],
      ];

  Widget _planCard(Map p) {
    final active = p['isActive'] == true;
    final milestones = tNum(p['milestoneCount']).toInt();
    final batches = tNum(p['assignedBatches']).toInt();
    final flocks = tNum(p['assignedFlocks']).toInt();
    return Opacity(
      opacity: active ? 1 : .6,
      child: TCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tStr(p['name']), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
                Text('${tStr(p['breed']).isNotEmpty ? 'For ${tStr(p['breed'])}' : 'Any breed'}${active ? '' : ' · Inactive'}',
                    style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
            ),
            if (_canEdit)
              IconButton(
                tooltip: 'Edit plan',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _editPlan(p),
              ),
            if (_canDelete)
              IconButton(
                tooltip: 'Delete plan',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 18, color: TColors.rose600),
                onPressed: () => _deletePlan(p),
              ),
          ]),
          if (tStr(p['description']).isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(tStr(p['description']), style: const TextStyle(fontSize: 13, color: TColors.slate600)),
          ],
          const SizedBox(height: 6),
          Text(
            '$milestones milestone${milestones == 1 ? '' : 's'} · used by $batches batch${batches == 1 ? '' : 'es'} and $flocks flock${flocks == 1 ? '' : 's'} directly',
            style: const TextStyle(fontSize: 12, color: TColors.slate500),
          ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------- assignments

  List<Widget> _assignmentsTab() => [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                t('Assign a plan to a '),
                b('batch'),
                t(' and all its flocks follow it; assign one to a '),
                b('flock'),
                t(' to override its batch.'),
              ]),
              style: const TextStyle(fontSize: 13, color: TColors.slate600),
            ),
          ),
          if (_canCreate) ...[
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _activeTemplates.isEmpty ? null : _assign,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Assign plan'),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        if (_assignments.isEmpty)
          _emptyCard(const [Text('No plan is assigned yet.', style: TextStyle(color: TColors.slate500))])
        else
          for (final a in _assignments) ...[_assignmentRow(a), const SizedBox(height: 8)],
      ];

  Widget _assignmentRow(Map a) {
    final isBatch = a['batchId'] != null;
    final count = tNum(a['flockCount']).toInt();
    final age = tNum(a['ageAtStartDays']).toInt();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
      child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: isBatch
                      ? 'Batch ${tStr(a['batchCode'])}${tStr(a['batchName']).isNotEmpty ? ' · ${tStr(a['batchName'])}' : ''}'
                      : 'Flock ${tStr(a['flockName'])}'),
              TextSpan(text: ' → ${tStr(a['templateName'])}', style: const TextStyle(color: TColors.slate500, fontWeight: FontWeight.w400)),
            ]),
            style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900),
          ),
          Text(
            '${isBatch ? '$count open flock${count == 1 ? '' : 's'}' : 'Overrides its batch'} · age at start ${age == 0 ? 'day-old' : formatAgeDays(age)}',
            style: const TextStyle(fontSize: 12, color: TColors.slate500),
          ),
          if (a['breedMismatch'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.warning_amber_rounded, size: 14, color: TColors.amber700),
                const SizedBox(width: 4),
                Flexible(
                  child: Text('Plan written for ${tStr(a['templateBreed'])}; this is ${tStr(a['targetBreed'])}.',
                      style: const TextStyle(fontSize: 12, color: TColors.amber700)),
                ),
              ]),
            ),
        ]),
        if (_canDelete)
          OutlinedButton.icon(
            onPressed: () => _removeAssignment(a),
            icon: const Icon(Icons.link_off, size: 16),
            label: const Text('Remove'),
          ),
      ]),
    );
  }
}

/// components/ui/prompt-dialog.tsx: a label, a text box, Cancel and confirm.
/// [onSubmit] throwing keeps the dialog open with the error under the box.
class LifecyclePromptDialog extends StatefulWidget {
  const LifecyclePromptDialog({
    super.key,
    required this.title,
    this.description,
    required this.label,
    required this.confirmLabel,
    required this.onSubmit,
    this.allowEmpty = false,
    this.options,
  });
  final String title;
  final String? description;
  final String label, confirmLabel;
  final bool allowEmpty;
  final Future<void> Function(String value) onSubmit;

  /// PromptDialog `options`: picked from this list; "Other" opens the box.
  final List<String>? options;

  @override
  State<LifecyclePromptDialog> createState() => _LifecyclePromptDialogState();
}

class _LifecyclePromptDialogState extends State<LifecyclePromptDialog> {
  final _text = TextEditingController();
  String? _error;
  bool _busy = false;
  String _choice = '';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final r = promptReasonValue(widget.options, _choice, _text.text, label: widget.label, allowEmpty: widget.allowEmpty);
    if (r.error != null) return setState(() => _error = r.error);
    final v = r.value!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(v);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: AlertDialog(
          scrollable: true,
          title: Text(widget.title),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (widget.description != null) ...[
                Text(widget.description!, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                const SizedBox(height: 12),
              ],
              Text(widget.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              if (widget.options != null)
                AppSelect<String>(
                  value: _choice.isEmpty ? null : _choice,
                  hintText: 'Select a reason',
                  items: [for (final o in widget.options!) AppSelectItem(value: o, label: o)],
                  onChanged: (v) => setState(() {
                    _choice = v ?? '';
                    _error = null;
                  }),
                ),
              if (widget.options == null || _choice == 'Other') ...[
                if (widget.options != null) const SizedBox(height: 8),
                AppTextarea(controller: _text, rows: 4),
              ],
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!, style: const TextStyle(fontSize: 13, color: TColors.rose700)),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: _busy ? null : _go,
              icon: _busy
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const SizedBox.shrink(),
              label: Text(widget.confirmLabel),
            ),
          ],
        ),
      );
}

// ------------------------------------------------------------ history dialog

class _HistoryDialog extends StatefulWidget {
  const _HistoryDialog({required this.api, required this.task, required this.offset});
  final LifecycleApi api;
  final Map task;
  final Duration offset;

  @override
  State<_HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<_HistoryDialog> {
  List<Map>? _events;

  @override
  void initState() {
    super.initState();
    widget.api
        .history(tIntOrNull(widget.task['flockId']) ?? 0, tIntOrNull(widget.task['milestoneId']) ?? 0)
        .then((r) => rowsOf(r), onError: (Object _) => <Map>[])
        .then((e) {
      if (mounted) setState(() => _events = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final events = _events;
    return AlertDialog(
      scrollable: true,
      title: Row(children: [
        const Icon(Icons.history, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(tStr(t['title']))),
      ]),
      content: SizedBox(
        width: 600,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${tStr(t['flockName'])} · ${milestoneAgeLabel(t['ageUnit'], t['ageValue'])} · due ${_day(t['dueDate'])}',
              style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 12),
          if (events == null)
            const LoadingLine('Loading…')
          else if (events.isEmpty)
            const Text('No history yet.', style: TextStyle(fontSize: 13, color: TColors.slate500))
          else
            for (final e in events) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${tStr(e['fromStatus'])} → ${tStr(e['toStatus'])}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate800)),
                  Text('${fmtInstant(e['atUtc'], widget.offset)}${tStr(e['actor']).isNotEmpty ? ' · ${tStr(e['actor'])}' : ''}',
                      style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  if (tStr(e['note']).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(tStr(e['note']), style: const TextStyle(fontSize: 13, color: TColors.slate700)),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
            ],
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------- plan editor

class _MilestoneRow {
  _MilestoneRow(this.key, [Map? from])
      : base = from == null ? {} : Map<String, dynamic>.from(from),
        ageUnit = tStr(from?['ageUnit']).isEmpty ? 'Week' : tStr(from?['ageUnit']),
        ageValue = from == null ? 0 : tNum(from['ageValue']),
        leadTimeDays = from == null ? 3 : tNum(from['leadTimeDays']),
        title = TextEditingController(text: tStr(from?['title'])),
        category = tStr(from?['category']),
        actionType = tStr(from?['actionType']).isEmpty ? null : tStr(from?['actionType']),
        description = TextEditingController(text: tStr(from?['description']));
  final int key;

  /// The milestone as read, so its id and order ride back on save.
  final Map<String, dynamic> base;
  String ageUnit;
  num ageValue;
  num leadTimeDays;
  final TextEditingController title;
  String category;
  String? actionType;
  final TextEditingController description;

  void dispose() {
    title.dispose();
    description.dispose();
  }
}

class _PlanEditorDialog extends StatefulWidget {
  const _PlanEditorDialog({required this.api, required this.template, required this.toast});
  final LifecycleApi api;
  final Map? template;
  final void Function(String title, {String? description, bool error}) toast;

  @override
  State<_PlanEditorDialog> createState() => _PlanEditorDialogState();
}

class _PlanEditorDialogState extends State<_PlanEditorDialog> {
  late final _name = TextEditingController(text: tStr(widget.template?['name']));
  late final _breed = TextEditingController(text: tStr(widget.template?['breed']));
  late final _description = TextEditingController(text: tStr(widget.template?['description']));
  late bool _active = widget.template == null ? true : widget.template!['isActive'] == true;
  final List<_MilestoneRow> _rows = [];
  int _nextKey = 1;
  List<String> _errors = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final ms = widget.template?['milestones'] is List ? [for (final m in widget.template!['milestones'] as List) if (m is Map) m] : <Map>[];
    for (var i = 0; i < ms.length; i++) {
      _rows.add(_MilestoneRow(i + 1, ms[i]));
    }
    if (_rows.isEmpty) _rows.add(_MilestoneRow(1));
    _nextKey = ms.length + 2;
  }

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
    _description.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final errs = validatePlan(_name.text, [
      for (final r in _rows) (title: r.title.text, ageUnit: r.ageUnit, ageValue: r.ageValue, leadTimeDays: r.leadTimeDays),
    ]);
    setState(() => _errors = errs);
    if (errs.isNotEmpty) return;
    setState(() => _saving = true);
    final input = <String, dynamic>{
      'name': _name.text.trim(),
      'breed': _breed.text.trim().isEmpty ? null : _breed.text.trim(),
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'isActive': _active,
      'milestones': [
        for (final r in _rows)
          {
            ...r.base,
            'ageUnit': r.ageUnit,
            'ageValue': r.ageValue,
            'title': r.title.text.trim(),
            'description': r.description.text,
            'category': r.category,
            'leadTimeDays': r.leadTimeDays,
            'actionType': (r.actionType ?? '').isEmpty ? null : r.actionType,
          },
      ],
    };
    try {
      final t = widget.template;
      if (t != null) {
        await widget.api.updateTemplate(tIntOrNull(t['templateId']) ?? 0, input);
      } else {
        await widget.api.createTemplate(input);
      }
      widget.toast(t != null ? 'Plan saved' : 'Plan created');
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      widget.toast('Could not save the plan', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _field(String label, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        const SizedBox(height: 4),
        child,
      ]);

  Widget _intInput(num value, ValueChanged<num> onChanged) => _IntField(value: value, onChanged: onChanged);

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Text(t != null ? 'Edit "${tStr(t['name'])}"' : 'New lifecycle plan'),
        content: SizedBox(
          width: 1000,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              "Your farm's own milestones. Ages are the birds' age, in days or weeks. Lead time is how many days ahead the reminder appears.",
              style: TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 16),
            _field('Plan name *', AppInput(controller: _name, hintText: 'e.g. Our layer plan')),
            const SizedBox(height: 12),
            _field('Breed (optional)', AppInput(controller: _breed, hintText: 'Any breed')),
            const SizedBox(height: 12),
            _field('Description', AppTextarea(controller: _description, rows: 2)),
            const SizedBox(height: 8),
            Row(children: [
              Switch(value: _active, onChanged: (v) => setState(() => _active = v)),
              const SizedBox(width: 8),
              const Text('Active', style: TextStyle(fontSize: 14, color: TColors.slate700)),
            ]),
            const SizedBox(height: 12),
            const Text('MILESTONES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .5, color: TColors.slate500)),
            const SizedBox(height: 8),
            for (var i = 0; i < _rows.length; i++) ...[_milestone(_rows[i], i), const SizedBox(height: 8)],
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => setState(() {
                  _rows.add(_MilestoneRow(_nextKey));
                  _nextKey += 1;
                }),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add milestone'),
              ),
            ),
            if (t != null) ...[
              const SizedBox(height: 6),
              const Text('Removing a milestone that already has task history retires it instead of deleting it.',
                  style: TextStyle(fontSize: 12, color: TColors.slate500)),
            ],
            if (_errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: TColors.rose50, border: Border.all(color: TColors.rose200), borderRadius: BorderRadius.circular(6)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final e in _errors) Text(e, style: const TextStyle(fontSize: 13, color: TColors.rose800)),
                ]),
              ),
            ],
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save plan'),
          ),
        ],
      ),
    );
  }

  Widget _milestone(_MilestoneRow r, int idx) => Container(
        key: ValueKey(r.key),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: _field('Age', _intInput(r.ageValue, (v) => setState(() => r.ageValue = v)))),
            const SizedBox(width: 8),
            Expanded(
              child: _field(
                'Unit',
                AppSelect<String>(
                  value: r.ageUnit,
                  items: [for (final (v, l) in lifecycleAgeUnits) AppSelectItem(value: v, label: l)],
                  onChanged: (v) => setState(() => r.ageUnit = v ?? r.ageUnit),
                ),
              ),
            ),
            if (_rows.length > 1)
              IconButton(
                tooltip: 'Remove milestone',
                icon: const Icon(Icons.delete_outline, size: 18, color: TColors.rose600),
                onPressed: () => setState(() {
                  _rows.remove(r);
                  r.dispose();
                }),
              ),
          ]),
          const SizedBox(height: 8),
          _field('Title * (Milestone ${idx + 1})', AppInput(controller: r.title, hintText: 'e.g. Review housing')),
          const SizedBox(height: 8),
          _field('Lead time (days)', _intInput(r.leadTimeDays, (v) => setState(() => r.leadTimeDays = v))),
          const SizedBox(height: 8),
          _field(
            'Category',
            Autocomplete<String>(
              initialValue: TextEditingValue(text: r.category),
              optionsBuilder: (v) => lifecycleCategorySuggestions.where((c) => c.toLowerCase().contains(v.text.toLowerCase())),
              onSelected: (v) => setState(() => r.category = v),
              fieldViewBuilder: (context, controller, focus, onSubmit) => TextFormField(
                controller: controller,
                focusNode: focus,
                decoration: const InputDecoration(hintText: 'e.g. Housing'),
                onChanged: (v) => r.category = v,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _field(
            'Action link (optional)',
            AppSelect<String>(
              value: r.actionType ?? 'none',
              items: [
                const AppSelectItem(value: 'none', label: 'No link'),
                for (final (v, l, _) in lifecycleActionTypes) AppSelectItem(value: v, label: l),
              ],
              onChanged: (v) => setState(() => r.actionType = v == null || v == 'none' ? null : v),
            ),
          ),
          const SizedBox(height: 8),
          _field('Description', AppInput(controller: r.description, hintText: 'What to check or prepare')),
        ]),
      );
}

/// A whole-number box that keeps its own text while the parent rebuilds.
class _IntField extends StatefulWidget {
  const _IntField({required this.value, required this.onChanged});
  final num value;
  final ValueChanged<num> onChanged;

  @override
  State<_IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<_IntField> {
  late final _c = TextEditingController(text: '${widget.value.toInt()}');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppNumberInput(
        controller: _c,
        onChanged: (v) => widget.onChanged((num.tryParse(v.trim()) ?? 0).floor()),
      );
}

// ------------------------------------------------------------ assign dialog

class _AssignDialog extends StatefulWidget {
  const _AssignDialog({required this.api, required this.templates, required this.batches, required this.flocks, required this.toast});
  final LifecycleApi api;
  final List<Map> templates, batches, flocks;
  final void Function(String title, {String? description, bool error}) toast;

  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  String? _templateId;
  String _target = 'batch';
  String? _targetId;
  num _weeks = 0, _days = 0;
  bool _saving = false;

  Future<void> _save() async {
    if (_templateId == null || _targetId == null) {
      widget.toast('Choose a plan and a batch or flock', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.api.assign({
        'templateId': int.parse(_templateId!),
        'batchId': _target == 'batch' ? int.parse(_targetId!) : null,
        'flockId': _target == 'flock' ? int.parse(_targetId!) : null,
        'ageAtStartDays': ageAtStartDays(_weeks, _days),
      });
      widget.toast('Plan assigned');
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      widget.toast('Could not assign the plan', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _field(String label, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        const SizedBox(height: 4),
        child,
      ]);

  Widget _choice(String k) {
    final on = _target == k;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() {
        _target = k;
        _targetId = null;
      }),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: on ? _indigo50 : null,
          border: Border.all(color: on ? _indigo500 : TColors.slate200, width: on ? 2 : 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k == 'batch' ? 'A batch' : 'One flock', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          Text(k == 'batch' ? 'All its flocks follow it' : "Overrides its batch's plan",
              style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tpl = widget.templates.where((t) => tStr(t['templateId']) == _templateId);
    final tplBreed = tpl.isEmpty ? '' : tStr(tpl.first['breed']);
    final targetRows = _target == 'batch'
        ? widget.batches.where((b) => tStr(b['batchId']) == _targetId)
        : widget.flocks.where((f) => tStr(f['flockId']) == _targetId);
    final targetBreed = targetRows.isEmpty ? '' : tStr(targetRows.first['breed']);
    final mismatch = tplBreed.isNotEmpty && targetBreed.isNotEmpty && tplBreed.trim().toLowerCase() != targetBreed.trim().toLowerCase();
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const Text('Assign a lifecycle plan'),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Re-assigning a batch or flock replaces its current plan; the old assignment is kept in history.',
                style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 16),
            _field(
              'Plan *',
              AppSelect<String>(
                value: _templateId,
                hintText: 'Choose a plan',
                items: [
                  for (final t in widget.templates)
                    AppSelectItem(
                      value: tStr(t['templateId']),
                      label: '${tStr(t['name'])}${tStr(t['breed']).isNotEmpty ? ' (${tStr(t['breed'])})' : ''}',
                    ),
                ],
                onChanged: (v) => setState(() => _templateId = v),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _choice('batch')),
              const SizedBox(width: 8),
              Expanded(child: _choice('flock')),
            ]),
            const SizedBox(height: 12),
            _field(
              _target == 'batch' ? 'Batch *' : 'Flock *',
              AppSelect<String>(
                key: ValueKey(_target),
                value: _targetId,
                hintText: _target == 'batch' ? 'Choose a batch' : 'Choose a flock',
                items: _target == 'batch'
                    ? [
                        for (final b in widget.batches)
                          AppSelectItem(value: tStr(b['batchId']), label: '${tStr(b['batchCode'])} · ${tStr(b['batchName'])}'),
                      ]
                    : [
                        for (final f in widget.flocks)
                          AppSelectItem(
                            value: tStr(f['flockId']),
                            label: '${tStr(f['name'])}${tStr(f['batchName']).isNotEmpty ? ' · ${tStr(f['batchName'])}' : ''}',
                          ),
                      ],
                onChanged: (v) => setState(() => _targetId = v),
              ),
            ),
            const SizedBox(height: 12),
            _field(
              "Birds' age on the flock's start date",
              Row(children: [
                Expanded(child: _IntField(value: _weeks, onChanged: (v) => _weeks = v)),
                const SizedBox(width: 6),
                const Text('weeks', style: TextStyle(fontSize: 13, color: TColors.slate500)),
                const SizedBox(width: 12),
                Expanded(child: _IntField(value: _days, onChanged: (v) => _days = v)),
                const SizedBox(width: 6),
                const Text('days', style: TextStyle(fontSize: 13, color: TColors.slate500)),
              ]),
            ),
            const SizedBox(height: 4),
            const Text(
              'Leave at 0 for day-old chicks. For birds bought older (e.g. point-of-lay pullets), enter their age when they arrived.',
              style: TextStyle(fontSize: 12, color: TColors.slate500),
            ),
            if (mismatch) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: TColors.amber200), borderRadius: BorderRadius.circular(6)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: TColors.amber900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('This plan was written for $tplBreed; this is $targetBreed. You can still assign it.',
                        style: const TextStyle(fontSize: 13, color: TColors.amber900)),
                  ),
                ]),
              ),
            ],
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Assign'),
          ),
        ],
      ),
    );
  }
}
