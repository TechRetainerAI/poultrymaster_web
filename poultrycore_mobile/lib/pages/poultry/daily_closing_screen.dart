import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/inputs.dart';
import '../../design/web_mobile.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../lookup_loader.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';
import '../shared/iam_permissions.dart';
import '../shared/reason_dialog.dart';
import 'poultry_links.dart';

/// Poultry → Tools → Daily Closing, as `app/poultry-daily-closing/page.tsx`
/// (migration 333) with `components/closing/daily-closing-parts.tsx`,
/// `daily-closing-dialogs.tsx` and `lib/closing/daily-closing.ts`.
///
/// One business date at a time: every section, the closing checklist, and
/// Close Business Day. A closed day shows its State At Closing and, if records
/// changed afterwards, what moved. Previous closings lists earlier days with
/// their figures as closed. Every figure is read from the workspace the Farm
/// API built; nothing is summed here.
///
/// Someone without the close right submits the day; someone with it closes
/// (approves) it, rejects a submission, or reopens a closed day.
class DailyClosingScreen extends StatefulWidget {
  const DailyClosingScreen({super.key, required this.session, required this.company, this.initialDate});
  final Session session;
  final Company company;

  /// A past day to open on, as `?date=`.
  final String? initialDate;

  @override
  State<DailyClosingScreen> createState() => _DailyClosingScreenState();
}

const closeRight = 'poultry.daily-closing.approve';

// ------------------------------------------------------------ pure helpers

/// closingStatusLabel: "Approved" is the workflow's word; "Closed" the meaning.
String closingStatusLabel(Map? record) => switch (record?['status']) {
      'Approved' => 'Closed',
      'Submitted' => 'Awaiting approval',
      'Rejected' => 'Rejected',
      'Draft' => 'Open',
      _ => 'Not closed',
    };

List<Map<String, dynamic>> _list(Object? v) => [
      if (v is List)
        for (final x in v)
          if (x is Map) Map<String, dynamic>.from(x),
    ];

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

num _n(Object? v) {
  final n = v is num ? v : num.tryParse('${v ?? ''}');
  return n == null || !n.isFinite ? 0 : n;
}

/// closeReadiness: why Close is disabled, in one sentence; null when it is not.
String? closeBlockReason(List<Map<String, dynamic>> checklist, Map? record) {
  final blockers = checklist.where((c) => c['status'] == 'Blocking').length;
  if (record?['status'] == 'Approved') return 'This day is already closed.';
  if (blockers == 1) return '1 blocking check must be resolved first.';
  if (blockers > 1) return '$blockers blocking checks must be resolved first.';
  return null;
}

const sectionLabels = {
  'production': 'Production',
  'sales': 'Sales',
  'cash': 'Cash',
  'inventory': 'Inventory',
  'expenses': 'Expenses',
  'outstanding': 'Outstanding items',
  'alerts': 'Alerts',
};

/// closingActionHref: where a checklist item's Resolve / Review goes. The
/// server sends a key, never a URL; unknown keys get no link.
String? closingActionHref(Object? action, Object? businessDate) {
  final date = toBusinessDate(businessDate);
  switch (action) {
    case 'missing-production':
      return date != null ? '/poultry-farm-completeness?date=$date' : '/poultry-farm-completeness';
    case 'unposted-batches':
      return date != null ? '/batch-production-records?date=$date' : '/batch-production-records';
    case 'production-records':
      return date != null ? '/production-records?date=$date' : '/production-records';
    case 'cash-count':
      return '/poultry-cash-reconciliation';
    case 'inventory':
      return '/poultry-raw-materials';
    case 'customer-balances':
      return date != null ? '/sales?date=$date' : '/customer-balances';
    case 'driver-returns':
      return date != null ? '/poultry-driver-returns?date=$date' : '/poultry-driver-returns';
    case 'previous-day':
      final prev = date != null ? shiftBusinessDate(date, -1) : null;
      return prev != null ? '/poultry-daily-closing?date=$prev' : null;
    default:
      return null;
  }
}

/// TRACKED_FIGURES: (section, label, kind, read).
final List<(String, String, String, num Function(Map<String, dynamic>))> trackedFigures = [
  ('production', 'Production records', 'count', (w) => _n(_map(w['production'])['records'])),
  ('production', 'Missing production', 'count', (w) => _n(_map(w['production'])['missingFlocks'])),
  ('production', 'Eggs produced', 'count', (w) => _n(_map(w['production'])['eggsProduced'])),
  ('production', 'Mortality', 'count', (w) => _n(_map(w['production'])['mortality'])),
  ('production', 'Feed used (kg)', 'quantity', (w) => _n(_map(w['production'])['feedKg'])),
  ('sales', 'Sales', 'money', (w) => _n(_map(w['sales'])['revenue'])),
  ('sales', 'Credit sales', 'money', (w) => _n(_map(w['sales'])['creditSales'])),
  ('sales', 'Payments received', 'money', (w) => _n(_map(w['sales'])['paymentsReceived'])),
  ('cash', 'Money in', 'money', (w) => _n(_map(w['cash'])['moneyIn'])),
  ('cash', 'Money out', 'money', (w) => _n(_map(w['cash'])['moneyOut'])),
  ('cash', 'Net cash flow', 'money', (w) => _n(_map(w['cash'])['netCashFlow'])),
  ('expenses', 'Expenses', 'money', (w) => _n(_map(w['expenses'])['total'])),
];

typedef FigureChange = ({String label, String kind, num atClose, num current, num delta});

/// diffClosingState: what changed after the day was closed. Money compares to
/// the cent, so floating-point noise never reports a phantom correction.
List<FigureChange> diffClosingState(Map<String, dynamic>? atClose, Map<String, dynamic>? current) {
  if (atClose == null || current == null) return const [];
  final out = <FigureChange>[];
  for (final (_, label, kind, read) in trackedFigures) {
    final a = read(atClose), c = read(current);
    final scale = kind == 'money' ? 100 : 1000;
    if ((a * scale).round() == (c * scale).round()) continue;
    out.add((label: label, kind: kind, atClose: a, current: c, delta: ((c - a) * scale).round() / scale));
  }
  return out;
}

/// productionSummaryLine.
String productionSummaryLine(Map<String, dynamic> ws) {
  final p = _map(ws['production']);
  if (_n(p['expectedFlocks']) == 0) return 'No flocks expected';
  if (_n(p['missingFlocks']) == 0) return 'Complete';
  return '${_n(p['missingFlocks'])} of ${_n(p['expectedFlocks'])} flocks missing';
}

String _qty(Object? n, [int digits = 0]) => fmtNum(_n(n), digits);
String _money(Object? n) => ghc(_n(n));

// Tailwind tones the web uses on this page.
const _emerald600 = Color(0xFF059669);
const _emerald700 = Color(0xFF047857);
const _rose700 = Color(0xFFBE123C);
const _amber800 = Color(0xFF92400E);
const _sky700 = Color(0xFF0369A1);
const _slate400 = Color(0xFF7F8EA3);  // a shade darker than Tailwind's, for legibility

// ------------------------------------------------------------------ screen

class _DailyClosingScreenState extends State<DailyClosingScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this)..addListener(_onTab);

  CompanyClock? _clock;

  /// Null = the company's today, decided by the server.
  late String? _picked = toBusinessDate(widget.initialDate);
  bool _mayClose = false;
  Map<String, dynamic>? _view;
  bool _loading = true;
  String? _error;
  bool _busy = false;
  bool _showAtClose = true;
  List<Map<String, dynamic>>? _history;

  ApiClient get _client => widget.session.farmClient;
  String get _farm => widget.company.farmId;
  String get _today => _clock?.today ?? isoDay(DateTime.now());

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final results = await Future.wait([
      CompanyClock.load(widget.session, widget.company),
      canDo(widget.session, widget.company, closeRight),
    ]);
    if (!mounted) return;
    setState(() {
      _clock = results[0] as CompanyClock;
      _mayClose = results[1] as bool;
    });
    await _load();
  }

  void _onTab() {
    if (_tabs.index == 1 && !_tabs.indexIsChanging) _loadHistory();
  }

  String? get _requested => _picked != null && _picked != _today ? _picked : null;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final v = await _client.get('/api/Poultry/daily-closings/day', query: {
        'farmId': _farm,
        if (_requested != null) 'businessDate': _requested,
      });
      if (!mounted) return;
      final view = _map(v);
      setState(() {
        _view = view;
        _showAtClose = _map(view['closing'])['isClosed'] == true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : 'Could not load the day.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadHistory() async {
    try {
      final res = await _client.get('/api/Poultry/daily-closings/history', query: {'farmId': _farm});
      if (mounted) setState(() => _history = _list(LookupLoader.rowsIn(res)));
    } on ApiException catch (e) {
      _toast('Could not load history', e.message);
    }
  }

  void _toast(String title, [String? detail]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(detail == null || detail.isEmpty ? title : '$title. $detail')),
    );
  }

  /// choose: a past day, or today (null). Always back to the Day tab.
  void _choose(String? value) {
    final d = toBusinessDate(value);
    setState(() => _picked = d == null || d.compareTo(_today) >= 0 ? null : d);
    _tabs.animateTo(0);
    _load();
  }

  Future<void> _pickDate(String shown) async {
    final today = businessDateAsDateTime(_today) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: businessDateAsDateTime(shown) ?? today,
      firstDate: DateTime(today.year - 5),
      lastDate: today,
    );
    if (d != null) _choose(isoDay(d));
  }

  /// run: one action, a toast, then reload. A 409 is the API refusing to close
  /// (a blocker, or already closed) and reloads so the page shows why.
  Future<bool> _run(Future<void> Function() fn, String ok) async {
    setState(() => _busy = true);
    try {
      await fn();
      _toast(ok);
      await _load();
      if (_history != null) _loadHistory();
      return true;
    } on ApiException catch (e) {
      final blocked = e.statusCode == 409;
      _toast(blocked ? 'The day was not closed' : 'That did not work', e.message);
      if (blocked) await _load();
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close(String businessDate, List<Map<String, dynamic>> warnings) async {
    final notes = await showDialog<String>(
      context: context,
      builder: (_) => _CloseDayDialog(businessDate: businessDate, warnings: warnings),
    );
    if (notes == null) return;
    await _run(
      () => _client.post('/api/Poultry/daily-closings/close', body: {
        'farmId': _farm,
        'businessDate': businessDate,
        'notes': notes.trim().isEmpty ? null : notes.trim(),
      }),
      '${formatLongDate(businessDate)} closed',
    );
  }

  Future<void> _reopen(Map record, String businessDate) async {
    final reason = await showReasonDialog(
      context,
      title: 'Reopen ${formatLongDate(businessDate)}?',
      description: 'The day will be open for correction. Its closing, who closed it and this reason stay in the history.',
      confirmLabel: 'Reopen Day',
    );
    if (reason == null) return;
    await _run(
      () => _client.post('/api/Poultry/daily-closings/${record['poultryDailyClosingId']}/reopen',
          query: {'farmId': _farm}, body: {'reason': reason}),
      'Day reopened',
    );
  }

  Future<void> _reject(Map record) async {
    final reason = await showReasonDialog(
      context,
      title: 'Reject this submission?',
      description: 'The person who submitted it will see your reason.',
      confirmLabel: 'Reject',
      destructive: true,
    );
    if (reason == null) return;
    await _run(
      () => _client.post('/api/Poultry/daily-closings/${record['poultryDailyClosingId']}/reject',
          query: {'farmId': _farm, 'reason': reason}),
      'Submission rejected',
    );
  }

  /// Submit for approval: start the day's closing record if there is none,
  /// then submit it, as the web's doSubmit.
  Future<void> _submit(Map? record, String businessDate) => _run(() async {
        var id = record?['poultryDailyClosingId'];
        if (id == null) {
          final created = await _client.post('/api/Poultry/daily-closings',
              body: {'closingDate': businessDate, 'farmId': _farm});
          id = _map(created)['poultryDailyClosingId'];
        }
        await _client.post('/api/Poultry/daily-closings/$id/submit', body: {
          'actualCashCounted': 0,
          'managerNotes': record?['managerNotes'],
          'farmId': _farm,
        });
      }, 'Submitted for approval');

  Future<void> _openPolicy() async {
    Map<String, dynamic> policy;
    try {
      policy = _map(await _client.get('/api/Poultry/daily-closings/policy', query: {'farmId': _farm}));
    } on ApiException catch (e) {
      _toast('Could not load the policy', e.message);
      return;
    }
    if (!mounted) return;
    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ClosingPolicyDialog(policy: policy),
    );
    if (saved == null) return;
    await _run(
      () => _client.put('/api/Poultry/daily-closings/policy', body: {...saved, 'farmId': _farm}),
      'Closing policy saved',
    );
  }

  Future<void> _viewSnapshot(Map event) async {
    Map<String, dynamic> ws;
    try {
      ws = _map(await _client.get('/api/Poultry/daily-closings/events/${event['eventId']}/snapshot',
          query: {'farmId': _farm}));
    } on ApiException catch (e) {
      _toast('Could not load that closing', e.message);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (page) => Scaffold(
        appBar: AppBar(
          title: Text('${formatLongDate(ws['businessDate'])} as closed '
              '(v${event['closeVersion'] ?? '?'}) by ${event['actor'] ?? 'unknown'}'),
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          AppCard(child: _Checklist(
            checks: _list(ws['checklist']),
            businessDate: '${ws['businessDate']}',
            onOpen: (href, label) {
              Navigator.of(page).pop();
              _follow(href, label);
            },
          )),
          const SizedBox(height: 12),
          _Sections(ws: ws),
        ]),
      ),
    ));
  }

  /// A checklist Resolve / Review link. The previous day is this page.
  void _follow(String href, String label) {
    final uri = Uri.parse(href);
    if (uri.path == '/poultry-daily-closing') {
      _choose(uri.queryParameters['date']);
      return;
    }
    openPoultryHref(context, widget.session, widget.company, href, label: label);
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-daily-closing');
    return Scaffold(
      appBar: AppBar(
        leading: lead.leading,
        leadingWidth: lead.width,
        title: const Text('Daily Closing'),
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Day'), Tab(text: 'Previous closings')]),
      ),
      body: TabBarView(controller: _tabs, children: [_dayTab(), _historyTab()]),
    );
  }

  Widget _header(String businessDate) {
    final tokens = context.tokens;
    final isToday = businessDate == _today;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text("Check that everything that should have happened today has, then close the day.",
          style: TextStyle(fontSize: 13, color: tokens.mutedForeground)),
      const SizedBox(height: 12),
      Text('Business date', style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
      const SizedBox(height: 4),
      Row(children: [
        IconButton.outlined(
          tooltip: 'Previous day',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _choose(shiftBusinessDate(businessDate, -1)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pickDate(businessDate),
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(formatLongDate(businessDate), overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(width: 6),
        IconButton.outlined(
          tooltip: 'Next day',
          icon: const Icon(Icons.chevron_right),
          onPressed: businessDate.compareTo(_today) >= 0 ? null : () => _choose(shiftBusinessDate(businessDate, 1)),
        ),
      ]),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (!isToday)
          AppButton(label: 'Today', variant: AppButtonVariant.ghost, size: AppButtonSize.sm, onPressed: () => _choose(null)),
        AppButton(
          label: 'Refresh',
          icon: Icons.refresh,
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.sm,
          busy: _loading,
          onPressed: _loading ? null : _load,
        ),
        if (_mayClose)
          AppButton(
            label: 'Policy',
            icon: Icons.tune,
            variant: AppButtonVariant.outline,
            size: AppButtonSize.sm,
            onPressed: _openPolicy,
          ),
      ]),
    ]);
  }

  Widget _dayTab() {
    final tokens = context.tokens;
    final view = _view;
    final live = view == null ? null : _map(view['live']);
    final record = view?['closing'] is Map ? _map(view!['closing']) : null;
    final isClosed = record?['isClosed'] == true;
    final atClose = view?['atClose'] is Map ? _map(view!['atClose']) : null;
    final businessDate = toBusinessDate(live?['businessDate']) ?? _picked ?? _today;
    final checklist = _list(live?['checklist']);
    final warnings = [for (final c in checklist) if (c['status'] == 'Warning') c];
    final reason = live == null ? null : closeBlockReason(checklist, record);
    final changes = isClosed ? diffClosingState(atClose, live) : const <FigureChange>[];
    final shown = isClosed && _showAtClose && atClose != null ? atClose : live;
    final counts = _map(live?['counts']);
    final canSubmit = !isClosed && record?['status'] != 'Submitted';
    final clock = _clock;
    String instant(Object? v) => clock?.instant(v) ?? '';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          _header(businessDate),
          const SizedBox(height: 12),
          if (_loading && view == null)
            Row(children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text('Checking the day…', style: TextStyle(fontSize: 13, color: tokens.mutedForeground)),
            ]),
          if (_error != null) _ErrorCard(_error!),
          if (live != null) ...[
            if (isClosed && record != null && atClose != null) ...[
              _ClosedSummary(record: record, atClose: atClose, instant: instant),
              const SizedBox(height: 12),
            ],
            if (changes.isNotEmpty) ...[_ChangesSinceClosing(changes: changes), const SizedBox(height: 12)],
            // ----------------------------------------- status + actions
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(formatLongDate(businessDate).toUpperCase(),
                    style: TextStyle(fontSize: 11.5, letterSpacing: .6, fontWeight: FontWeight.w500, color: tokens.mutedForeground)),
                const SizedBox(height: 2),
                Text(closingStatusLabel(record), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                Text(
                  '${_n(counts['blocking'])} blocking · ${_n(counts['warning'])} warning${_n(counts['warning']) == 1 ? '' : 's'} '
                  '· ${_n(counts['complete'])} complete',
                  style: TextStyle(fontSize: 13, color: tokens.mutedForeground),
                ),
                if (record?['status'] == 'Submitted')
                  Text('Submitted by ${record?['submittedBy'] ?? 'unknown'} — waiting for someone with the close right.',
                      style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
                if (record?['status'] == 'Rejected' && '${record?['rejectionReason'] ?? ''}'.isNotEmpty)
                  Text('Rejected: ${record?['rejectionReason']}', style: const TextStyle(fontSize: 12, color: _rose700)),
                if (!isClosed && '${record?['lastReopenReason'] ?? ''}'.isNotEmpty)
                  Text(
                    'Reopened by ${record?['lastReopenedBy'] ?? 'unknown'} (${instant(record?['lastReopenedAtUtc'])}): '
                    '${record?['lastReopenReason']}',
                    style: const TextStyle(fontSize: 12, color: _amber800),
                  ),
                if (!isClosed && reason != null) Text(reason, style: const TextStyle(fontSize: 12, color: _rose700)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (isClosed && _mayClose && record != null)
                    AppButton(
                      label: 'Reopen Day',
                      icon: Icons.lock_open,
                      variant: AppButtonVariant.outline,
                      onPressed: _busy ? null : () => _reopen(record, businessDate),
                    ),
                  if (!isClosed && record?['status'] == 'Submitted' && _mayClose)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: _rose700),
                      onPressed: _busy ? null : () => _reject(record!),
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Reject'),
                    ),
                  if (!isClosed && !_mayClose && canSubmit)
                    AppButton(
                      label: 'Submit for approval',
                      icon: Icons.send,
                      variant: AppButtonVariant.outline,
                      onPressed: _busy ? null : () => _submit(record, businessDate),
                    ),
                  if (!isClosed && _mayClose)
                    Tooltip(
                      message: reason ?? '',
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: _emerald600),
                        onPressed: _busy || reason != null ? null : () => _close(businessDate, warnings),
                        icon: const Icon(Icons.lock, size: 18),
                        label: const Text('Close Business Day'),
                      ),
                    ),
                ]),
                const SizedBox(height: 12),
                Text('CLOSING CHECKLIST${isClosed ? ' (CURRENT)' : ''}',
                    style: TextStyle(fontSize: 11.5, letterSpacing: .6, fontWeight: FontWeight.w600, color: tokens.mutedForeground)),
                _Checklist(checks: checklist, businessDate: businessDate, onOpen: _follow),
              ]),
            ),
            const SizedBox(height: 12),
            // ------------------------------------------------- sections
            if (isClosed && atClose != null) ...[
              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('Showing:', style: TextStyle(fontSize: 13, color: tokens.mutedForeground)),
                AppButton(
                  label: 'State at closing',
                  size: AppButtonSize.sm,
                  variant: _showAtClose ? AppButtonVariant.primary : AppButtonVariant.outline,
                  onPressed: () => setState(() => _showAtClose = true),
                ),
                AppButton(
                  label: 'Current corrected state',
                  size: AppButtonSize.sm,
                  variant: !_showAtClose ? AppButtonVariant.primary : AppButtonVariant.outline,
                  onPressed: () => setState(() => _showAtClose = false),
                ),
              ]),
              const SizedBox(height: 10),
            ],
            if (shown != null) _Sections(ws: shown),
            const SizedBox(height: 12),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('HISTORY OF THIS DAY',
                    style: TextStyle(fontSize: 11.5, letterSpacing: .6, fontWeight: FontWeight.w600, color: tokens.mutedForeground)),
                const SizedBox(height: 6),
                _Timeline(events: _list(view?['history']), instant: instant, onViewSnapshot: _viewSnapshot),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _historyTab() {
    final tokens = context.tokens;
    final history = _history;
    final clock = _clock;
    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          if (history == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (history.isEmpty)
            Text('No days have been closed yet.', style: TextStyle(color: tokens.mutedForeground))
          else
            for (final (i, h) in history.indexed) ...[
              _HistoryCard(
                row: h,
                stripe: i.isOdd,
                instant: (v) => clock?.instant(v) ?? '',
                onOpen: () => _choose(toBusinessDate(h['closingDate'])),
              ),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 4),
          Text('Figures are as each day was closed. Days closed before this version show their status only.',
              style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- pieces

class _ErrorCard extends StatelessWidget {
  const _ErrorCard(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F2),
          border: Border.all(color: const Color(0xFFFECDD3)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(message, style: const TextStyle(fontSize: 13, color: Color(0xFF9F1239))),
      );
}

/// Stat: a label over a figure, toned good / bad / muted.
class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.tone});
  final String label;
  final String value;
  final String? tone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = switch (tone) {
      'good' => _emerald700,
      'bad' => _rose700,
      'muted' => _slate400,
      _ => tokens.cardForeground,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.card,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: TextStyle(fontSize: 10.5, letterSpacing: .4, color: tokens.mutedForeground)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

/// Section: a titled card with a two-column grid of stats.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.stats, this.note});
  final String title;
  final List<_Stat> stats;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title.toUpperCase(),
            style: TextStyle(fontSize: 11.5, letterSpacing: .6, fontWeight: FontWeight.w600, color: tokens.mutedForeground)),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 8) / 2;
          return Wrap(spacing: 8, runSpacing: 8, children: [for (final s in stats) SizedBox(width: w, child: s)]);
        }),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(note!, style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
        ],
      ]),
    );
  }
}

/// PRODUCTION · SALES · CASH · EXPENSES · INVENTORY · OUTSTANDING.
class _Sections extends StatelessWidget {
  const _Sections({required this.ws});
  final Map<String, dynamic> ws;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final p = _map(ws['production']);
    final s = _map(ws['sales']);
    final c = _map(ws['cash']);
    final e = _map(ws['expenses']);
    final inv = _map(ws['inventory']);
    final o = _map(ws['outstanding']);
    final negative = _list(inv['negativeStock']);
    final lowFeed = _list(inv['lowFeed']);
    final lowStock = _list(inv['lowStock']);
    final missing = _n(p['missingFlocks']);
    final reconciliations = _n(c['reconciliations']);
    final receivables = _n(s['receivablesChange']);
    String unit(Map i) => '${i['unit'] ?? ''}';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Section(title: 'Production', stats: [
        _Stat(
          'Production records',
          _n(p['expectedFlocks']) == 0 ? 'None expected' : '${_qty(p['reportedFlocks'])} / ${_qty(p['expectedFlocks'])} expected',
          tone: missing > 0 ? 'bad' : null,
        ),
        _Stat('Eggs produced', _qty(p['eggsProduced'])),
        _Stat('Damaged eggs', _qty(p['eggsDamaged'])),
        _Stat('Mortality', _qty(p['mortality'])),
        _Stat('Feed used', '${_qty(p['feedKg'], 2)} kg'),
        _Stat('Missing production', _qty(missing), tone: missing > 0 ? 'bad' : 'good'),
      ]),
      const SizedBox(height: 12),
      _Section(
        title: 'Sales',
        note: 'Sales are revenue. Payments received settle earlier credit and are not added to revenue.',
        stats: [
          _Stat('Sales recorded', _qty(s['count'])),
          _Stat('Amount', _money(s['revenue'])),
          _Stat('Cash sales', _money(s['cashSales'])),
          _Stat('Credit sales', _money(s['creditSales']), tone: _n(s['creditSales']) > 0 ? 'bad' : null),
          _Stat('Payments received',
              '${_money(s['paymentsReceived'])}${_n(s['paymentsCount']) != 0 ? ' (${_qty(s['paymentsCount'])})' : ''}'),
          _Stat('Customer balances', '${receivables > 0 ? '+' : ''}${_money(receivables)}',
              tone: receivables > 0 ? 'bad' : receivables < 0 ? 'good' : null),
        ],
      ),
      const SizedBox(height: 12),
      _Section(
        title: 'Cash',
        note: reconciliations > 0
            ? 'From ${_qty(reconciliations)} posted cash count${reconciliations == 1 ? '' : 's'} for this day.'
            : 'Expected vs actual appears once a cash count is posted for this day.',
        stats: [
          _Stat('Money in today', _money(c['moneyIn']), tone: 'good'),
          _Stat('Money out today', _money(c['moneyOut']), tone: 'bad'),
          _Stat('Net cash flow', _money(c['netCashFlow']), tone: _n(c['netCashFlow']) < 0 ? 'bad' : null),
          if (reconciliations > 0) ...[
            _Stat('Expected cash', _money(c['expectedCash'])),
            _Stat('Actual (counted)', _money(c['actualCash'])),
            _Stat('Difference', _money(c['difference']), tone: _n(c['difference']) == 0 ? 'good' : 'bad'),
          ],
        ],
      ),
      const SizedBox(height: 12),
      _Section(
        title: 'Expenses',
        note: 'Non-cash covers depreciation, internal usage and consumption recognition.',
        stats: [
          _Stat('Expenses recorded', '${_qty(e['count'])} · ${_money(e['total'])}'),
          _Stat('Cash (paid)', _money(e['cash'])),
          _Stat('Credit (unpaid)', _money(e['credit']), tone: _n(e['credit']) > 0 ? 'bad' : null),
          _Stat('Non-cash', _money(e['nonCash']), tone: 'muted'),
        ],
      ),
      const SizedBox(height: 12),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('INVENTORY',
              style: TextStyle(fontSize: 11.5, letterSpacing: .6, fontWeight: FontWeight.w600, color: tokens.mutedForeground)),
          const SizedBox(height: 6),
          if (negative.isEmpty && lowFeed.isEmpty && lowStock.isEmpty)
            const Row(children: [
              Icon(Icons.check_circle_outline, size: 16, color: _emerald700),
              SizedBox(width: 6),
              Text('No stock exceptions.', style: TextStyle(fontSize: 13, color: _emerald700)),
            ])
          else ...[
            for (final i in negative)
              Text('${i['item']}: negative stock (${_qty(i['quantity'], 2)} ${unit(i)})',
                  style: const TextStyle(fontSize: 13, color: _rose700)),
            for (final i in lowFeed)
              Text(
                '${i['item']}: about ${i['daysRemaining']} days remaining (${_qty(i['quantity'], 2)} ${unit(i)} at '
                '${_qty(i['dailyUse'], 2)}/day)',
                style: const TextStyle(fontSize: 13, color: _amber800),
              ),
            for (final i in lowStock)
              Text('${i['item']}: ${_qty(i['quantity'], 2)} ${unit(i)} (reorder at ${_qty(i['minimum'], 2)})',
                  style: const TextStyle(fontSize: 13, color: _amber800)),
          ],
          const SizedBox(height: 6),
          Text('Stock levels are current, not as of this date.',
              style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
        ]),
      ),
      const SizedBox(height: 12),
      _Section(title: 'Outstanding items', stats: [
        _Stat('Unposted batch production', _qty(o['unpostedBatches']), tone: _n(o['unpostedBatches']) > 0 ? 'bad' : null),
        _Stat('Draft driver returns', _qty(o['draftDriverReturns']), tone: _n(o['draftDriverReturns']) > 0 ? 'bad' : null),
        _Stat('Loadings with no return', _qty(o['loadingsWithoutReturn']),
            tone: _n(o['loadingsWithoutReturn']) > 0 ? 'bad' : null),
        _Stat('Previous day', o['previousDayClosed'] == true ? 'Closed' : 'Not closed',
            tone: o['previousDayClosed'] == true ? 'good' : null),
      ]),
    ]);
  }
}

/// CLOSING CHECKLIST: blocking first, then warnings, then complete (server order).
class _Checklist extends StatelessWidget {
  const _Checklist({required this.checks, required this.businessDate, required this.onOpen});
  final List<Map<String, dynamic>> checks;
  final String businessDate;
  final void Function(String href, String label) onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(children: [
      for (final (i, c) in checks.indexed) ...[
        if (i > 0) Divider(height: 1, color: tokens.border),
        Builder(builder: (context) {
          final status = '${c['status']}';
          final (icon, color) = switch (status) {
            'Complete' => (Icons.check_circle_outline, const Color(0xFF059669)),
            'Warning' => (Icons.warning_amber_rounded, const Color(0xFFD97706)),
            _ => (Icons.block, const Color(0xFFE11D48)),
          };
          final href = status == 'Complete' ? null : closingActionHref(c['action'], businessDate);
          final linkLabel = status == 'Blocking' ? 'Resolve' : 'Review';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 16, color: color, semanticLabel: status)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(
                    text: '${c['title'] ?? ''}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: status == 'Complete' ? FontWeight.w400 : FontWeight.w500,
                      color: status == 'Complete' ? tokens.mutedForeground : tokens.cardForeground,
                    ),
                    children: [
                      TextSpan(
                        text: '  ${(sectionLabels[c['section']] ?? '${c['section'] ?? ''}').toUpperCase()}',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w400, letterSpacing: .4, color: _slate400),
                      ),
                    ],
                  )),
                  if ('${c['description'] ?? ''}'.isNotEmpty)
                    Text('${c['description']}', style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
                ]),
              ),
              if (href != null)
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: _sky700,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () => onOpen(href, '${c['title'] ?? linkLabel}'),
                  child: Text(linkLabel, style: const TextStyle(fontWeight: FontWeight.w500)),
                ),
            ]),
          );
        }),
      ],
    ]);
  }
}

/// "September 20, 2026 — CLOSED" and the headline figures as closed.
class _ClosedSummary extends StatelessWidget {
  const _ClosedSummary({required this.record, required this.atClose, required this.instant});
  final Map<String, dynamic> record;
  final Map<String, dynamic> atClose;
  final String Function(Object?) instant;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final version = _n(record['closeVersion']);
    Widget line(String k, String v) => Text.rich(TextSpan(
          text: '$k: ',
          style: TextStyle(fontSize: 13, color: tokens.mutedForeground),
          children: [TextSpan(text: v, style: TextStyle(fontWeight: FontWeight.w500, color: tokens.cardForeground))],
        ));
    return Container(
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, color: const Color(0xFF10B981)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  const Icon(Icons.lock, size: 16, color: _emerald600),
                  Text.rich(TextSpan(
                    text: '${formatLongDate(atClose['businessDate'])} — ',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    children: const [TextSpan(text: 'CLOSED', style: TextStyle(color: _emerald700))],
                  )),
                  if (version > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: tokens.muted, borderRadius: BorderRadius.circular(999)),
                      child: Text('closed ${_qty(version)} times', style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
                    ),
                ]),
                const SizedBox(height: 8),
                line('Production', productionSummaryLine(atClose)),
                line('Sales', _money(_map(atClose['sales'])['revenue'])),
                line('Money in', _money(_map(atClose['cash'])['moneyIn'])),
                line('Money out', _money(_map(atClose['cash'])['moneyOut'])),
                line('Net cash flow', _money(_map(atClose['cash'])['netCashFlow'])),
                line('Warnings at closing', '${record['warningsAtClose'] ?? _map(atClose['counts'])['warning'] ?? 0}'),
                const SizedBox(height: 8),
                Text(
                  'Closed by ${record['closedBy'] ?? 'unknown'} · ${instant(record['closedAtUtc'])}'
                  '${'${record['managerNotes'] ?? ''}'.isNotEmpty ? ' · “${record['managerNotes']}”' : ''}',
                  style: TextStyle(fontSize: 12, color: tokens.mutedForeground),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// State At Closing vs Current Corrected State, for the figures that moved.
class _ChangesSinceClosing extends StatelessWidget {
  const _ChangesSinceClosing({required this.changes});
  final List<FigureChange> changes;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF78350F);
    String show(FigureChange c, num v) => c.kind == 'money' ? _money(v) : _qty(v, c.kind == 'quantity' ? 2 : 0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x99FFFBEB),
        border: Border.all(color: const Color(0xFFFDE68A)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: ink),
          SizedBox(width: 6),
          Expanded(
            child: Text('Changed since closing', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink)),
          ),
        ]),
        const SizedBox(height: 4),
        const Text(
          'Records for this day were added or corrected after it was closed. The closing keeps what it was closed '
          'with; reopen and close again to adopt the corrected figures.',
          style: TextStyle(fontSize: 12, color: Color(0xCC78350F)),
        ),
        for (final c in changes)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.only(top: 8),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xB3FDE68A)))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(c.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                Text('${c.delta > 0 ? '+' : ''}${show(c, c.delta)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
              Text('State at closing ${show(c, c.atClose)} → Current corrected state ${show(c, c.current)}',
                  style: const TextStyle(fontSize: 12, color: Color(0xCC78350F))),
            ]),
          ),
      ]),
    );
  }
}

const _eventLabels = {
  'Created': 'Started',
  'Submitted': 'Submitted for approval',
  'Rejected': 'Rejected',
  'Closed': 'Closed',
  'Reopened': 'Reopened',
  'Recreated': 'Recreated',
  'Deleted': 'Deleted',
};

/// Who did what to this day, and why — newest first.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.events, required this.instant, required this.onViewSnapshot});
  final List<Map<String, dynamic>> events;
  final String Function(Object?) instant;
  final void Function(Map event) onViewSnapshot;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (events.isEmpty) {
      return Text('Nothing has been recorded for this day yet.', style: TextStyle(fontSize: 13, color: tokens.mutedForeground));
    }
    return Column(children: [
      for (final e in events.reversed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.history, size: 16, color: _slate400)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(style: const TextStyle(fontSize: 13), children: [
                  TextSpan(
                    text: _eventLabels[e['eventType']] ?? '${e['eventType']}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  if (e['eventType'] == 'Closed' && _n(e['closeVersion']) > 0)
                    TextSpan(
                        text: ' (v${_qty(e['closeVersion'])}'
                            '${_n(e['warningCount']) > 0 ? ', ${_qty(e['warningCount'])} warnings' : ''})'),
                  TextSpan(text: ' by ${e['actor'] ?? 'unknown'}'),
                ])),
                Text(instant(e['occurredAtUtc']), style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
                if ('${e['reason'] ?? ''}'.isNotEmpty) Text('Reason: ${e['reason']}', style: const TextStyle(fontSize: 12)),
              ]),
            ),
            if (e['hasSnapshot'] == true)
              TextButton(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => onViewSnapshot(e),
                child: const Text('View as closed', style: TextStyle(fontSize: 12)),
              ),
          ]),
        ),
    ]);
  }
}

/// One previous closing, as the web's MobileCardList row: date, who closed
/// it, a status badge, Sales / Net cash tiles, details, and Open day.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.row, required this.stripe, required this.instant, required this.onOpen});
  final Map<String, dynamic> row;
  final bool stripe;
  final String Function(Object?) instant;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final h = row;
    final closed = h['isClosed'] == true;
    final reopen = _n(h['reopenCount']);
    final net = h['netCashFlow'];
    final secondary = h['closedBy'] != null
        ? 'Closed by ${h['closedBy']}${h['closedAtUtc'] != null ? ' · ${instant(h['closedAtUtc'])}' : ''}'
        : closingStatusLabel(h);
    Widget tile(String label, String value, Color accent) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: accent.withValues(alpha: .08), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 11, color: tokens.mutedForeground)),
              Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: accent)),
            ]),
          ),
        );
    Widget detail(String k, String v) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 140, child: Text(k, style: TextStyle(fontSize: 12.5, color: tokens.mutedForeground))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: stripe ? const Color(0xFFF8FAFC) : tokens.card,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(formatLongDate(h['closingDate']), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text(secondary, style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: closed ? const Color(0xFFD1FAE5) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(closingStatusLabel(h),
                style: TextStyle(fontSize: 12, color: closed ? _emerald700 : const Color(0xFF475569))),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          tile('Sales', h['revenue'] != null ? _money(h['revenue']) : '—', _emerald700),
          const SizedBox(width: 8),
          tile('Net cash', net != null ? _money(net) : '—', _n(net) < 0 ? _rose700 : const Color(0xFF1D4ED8)),
        ]),
        const SizedBox(height: 6),
        detail('Warnings at closing', '${h['warningsAtClose'] ?? '—'}'),
        detail('Eggs produced', h['eggsProduced'] != null ? _qty(h['eggsProduced']) : '—'),
        detail(
          'Reopened',
          reopen > 0 ? '${_qty(reopen)}×${'${h['lastReopenReason'] ?? ''}'.isNotEmpty ? ' — ${h['lastReopenReason']}' : ''}' : '—',
        ),
        const SizedBox(height: 8),
        AppButton(label: 'Open day', variant: AppButtonVariant.outline, fullWidth: true, onPressed: onOpen),
      ]),
    );
  }
}

// --------------------------------------------------------------- dialogs

/// "Close September 20, 2026?" with the warnings it closes with and optional
/// notes. Completes with the notes, or null when cancelled.
class _CloseDayDialog extends StatefulWidget {
  const _CloseDayDialog({required this.businessDate, required this.warnings});
  final String businessDate;
  final List<Map<String, dynamic>> warnings;

  @override
  State<_CloseDayDialog> createState() => _CloseDayDialogState();
}

class _CloseDayDialogState extends State<_CloseDayDialog> {
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.warnings;
    return AlertDialog(
      title: Text('Close ${formatLongDate(widget.businessDate)}?'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text(
            'This records the day as checked and stores its figures as they are now. Later corrections stay possible '
            'and will show as changes against this closing.',
            style: TextStyle(fontSize: 13),
          ),
          if (w.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                border: Border.all(color: const Color(0xFFFDE68A)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFF78350F)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Closing with ${w.length} warning${w.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF78350F))),
                  ),
                ]),
                const SizedBox(height: 4),
                for (final x in w)
                  Text('• ${x['title'] ?? ''}', style: const TextStyle(fontSize: 13, color: Color(0xFF78350F))),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          const Text('Notes (optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          AppTextarea(controller: _notes, rows: 2, hintText: 'e.g. Feed order placed for tomorrow'),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _emerald600),
          onPressed: () => Navigator.pop(context, _notes.text),
          child: const Text('Close Business Day'),
        ),
      ],
    );
  }
}

const _levelRows = [
  ('missingProduction', 'Missing flock production'),
  ('unpostedProduction', 'Unposted batch production'),
  ('impossibleBirdCounts', 'Impossible bird counts'),
  ('pendingDriverReturns', 'Pending driver returns'),
  ('negativeStock', 'Negative stock'),
  ('cashDifference', 'Cash count difference'),
];

/// "Closing policy": which checks block a close, and the thresholds.
/// Completes with the policy to save, or null when cancelled.
class _ClosingPolicyDialog extends StatefulWidget {
  const _ClosingPolicyDialog({required this.policy});
  final Map<String, dynamic> policy;

  @override
  State<_ClosingPolicyDialog> createState() => _ClosingPolicyDialogState();
}

class _ClosingPolicyDialogState extends State<_ClosingPolicyDialog> {
  late final Map<String, dynamic> _draft = {
    for (final (k, _) in _levelRows) k: widget.policy[k] == 'Blocking' ? 'Blocking' : 'Warning',
    'requireCashCount': widget.policy['requireCashCount'] == true,
  };
  late final _tolerance = TextEditingController(text: fmtNum(_n(widget.policy['cashDifferenceTolerance']), 2).replaceAll(',', ''));
  late final _lowFeed = TextEditingController(text: fmtNum(_n(widget.policy['lowFeedDays']), 2).replaceAll(',', ''));
  late final _mortality = TextEditingController(text: fmtNum(_n(widget.policy['unusualMortalityPct']), 2).replaceAll(',', ''));

  @override
  void dispose() {
    for (final c in [_tolerance, _lowFeed, _mortality]) {
      c.dispose();
    }
    super.dispose();
  }

  /// setNum: empty is 0, negatives are 0.
  num _num(TextEditingController c) {
    final v = double.tryParse(c.text.trim());
    return v == null || v < 0 ? 0 : v;
  }

  @override
  Widget build(BuildContext context) {
    Widget numField(String label, TextEditingController c) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            AppNumberInput(controller: c, allowDecimal: true),
          ],
        );
    return AlertDialog(
      title: const Text('Closing policy'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              'Choose which checks stop a day from being closed. Anything set to Warning is shown but never blocks.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            for (final (key, label) in _levelRows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
                  SizedBox(
                    width: 130,
                    child: AppSelect<String>(
                      value: _draft[key] as String,
                      items: const [
                        AppSelectItem(value: 'Blocking', label: 'Blocking'),
                        AppSelectItem(value: 'Warning', label: 'Warning'),
                      ],
                      onChanged: (v) => setState(() => _draft[key] = v ?? 'Warning'),
                    ),
                  ),
                ]),
              ),
            const Divider(height: 20),
            numField('Cash difference tolerance', _tolerance),
            const SizedBox(height: 8),
            numField('Low feed below (days)', _lowFeed),
            const SizedBox(height: 8),
            numField('Unusual mortality above (%)', _mortality),
            const SizedBox(height: 8),
            Row(children: [
              const Expanded(child: Text('Warn when no cash count is posted for the day', style: TextStyle(fontSize: 14))),
              Switch(
                value: _draft['requireCashCount'] == true,
                onChanged: (v) => setState(() => _draft['requireCashCount'] = v),
              ),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            ..._draft,
            'cashDifferenceTolerance': _num(_tolerance),
            'lowFeedDays': _num(_lowFeed),
            'unusualMortalityPct': _num(_mortality),
          }),
          child: const Text('Save policy'),
        ),
      ],
    );
  }
}
