// Poultry → Tools → Recurring Expenses (components/recurring/recurring-expenses-page.tsx,
// migration 348): rent, security, internet … set up once. When one falls due it
// waits as a draft to check and post; nothing is paid or recorded until then.
//
//   To review   drafts raised when due: edit amount, date or account, then Post or Skip
//   Upcoming    what falls due in the next 7 / 30 days
//   Templates   create, edit, pause, resume, end, delete

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../reports/report_format.dart';
import '../reports/report_routes.dart' show openAppHref;
import '../sales/balances_widgets.dart' show LoadingLine;
import '../sales/payments_received_screen.dart' show fmtDateTimeLike;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';
import 'recurring_logic.dart';

typedef RecurringOption = ({int id, String name});

/// ModuleLookups for Poultry: free-text categories, its suppliers and active
/// cash accounts; Poultry posts without an approval step.
class RecurringLookups {
  const RecurringLookups({this.suppliers = const [], this.cashAccounts = const []});
  final List<RecurringOption> suppliers;
  final List<RecurringOption> cashAccounts;
  bool get moduleApproves => false;
  String get expensesHref => '/expenses';
  List<String> get textCategories => poultryRecurringCategories;
}

class RecurringExpensesScreen extends StatefulWidget {
  const RecurringExpensesScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RecurringExpensesScreen> createState() => _RecurringExpensesScreenState();
}

class _RecurringExpensesScreenState extends State<RecurringExpensesScreen> {
  String _tab = 'review';
  RecurringLookups? _lookups;
  List<Map> _templates = [], _occurrences = [], _upcoming = [];
  int _days = 30;
  String _occView = 'Open';
  bool _loading = true;
  int? _busy;
  FarmMoney _gh = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  Map<String, dynamic> _q([Map<String, dynamic> extra = const {}]) => {'farmId': _farmId, ...extra};

  /// poultry.expenses.create/edit/delete: anyone but Staff on the phone.
  bool get _canWrite => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    _start();
  }

  Future<void> _start() async {
    setState(() => _loading = true);
    // Raise anything that has fallen due first. Idempotent.
    if (_canWrite) {
      try {
        final g = await _api.post('/api/recurring-expenses/generate?farmId=${Uri.encodeQueryComponent(_farmId)}', body: {});
        final fails = g is Map && g['autoPostFailures'] is List ? [for (final f in g['autoPostFailures'] as List) '$f'] : <String>[];
        if (fails.isNotEmpty && mounted) {
          trackerToast(context, 'Some automatic posts need attention', description: fails.join('; '), error: true);
        }
      } on ApiException {
        // As the web: a failed generate is not shown.
      }
    }
    await _loadLookups();
    await _reload();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadLookups() async {
    List<Map> cash = [], sup = [];
    try {
      cash = rowsOf(await _api.get('/api/Poultry/cash-accounts', query: _q()));
    } on ApiException {
      cash = [];
    }
    try {
      sup = rowsOf(await _api.get('/api/Supplier', query: {'userId': widget.session.tokens.userId, 'farmId': _farmId}));
    } on ApiException {
      sup = [];
    }
    if (!mounted) return;
    setState(() => _lookups = RecurringLookups(
          suppliers: [for (final s in sup) (id: tIntOrNull(s['supplierId']) ?? 0, name: tStr(s['name']))],
          cashAccounts: [
            for (final a in cash)
              if (a['isActive'] == true) (id: tIntOrNull(a['poultryCashAccountId']) ?? 0, name: tStr(a['accountName'])),
          ],
        ));
  }

  Future<void> _reloadOccurrences() async {
    try {
      final r = await _api.get('/api/recurring-expenses/occurrences', query: _q({'status': _occView}));
      if (mounted) setState(() => _occurrences = rowsOf(r));
    } on ApiException {
      if (mounted) setState(() => _occurrences = []);
    }
  }

  Future<void> _reloadUpcoming() async {
    try {
      final r = await _api.get('/api/recurring-expenses/upcoming', query: _q({'days': '$_days'}));
      if (mounted) setState(() => _upcoming = rowsOf(r));
    } on ApiException {
      // As the web: keep what is shown.
    }
  }

  Future<void> _reload() async {
    try {
      final r = await Future.wait([
        _api.get('/api/recurring-expenses/templates', query: _q()),
        _api.get('/api/recurring-expenses/upcoming', query: _q({'days': '$_days'})),
      ]);
      if (mounted) {
        setState(() {
          _templates = rowsOf(r[0]);
          _upcoming = rowsOf(r[1]);
        });
      }
      await _reloadOccurrences();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load recurring expenses', description: e.message, error: true);
    }
  }

  String? _cashName(Object? id) => _lookups?.cashAccounts.where((a) => a.id == tIntOrNull(id)).map((a) => a.name).firstOrNull;
  String? _supplierName(Object? id) => _lookups?.suppliers.where((a) => a.id == tIntOrNull(id)).map((a) => a.name).firstOrNull;

  Future<void> _post(Map o) async {
    // "Paid" with no cash account would be recorded as paid while no money
    // leaves any account, so send the user to choose one first.
    if (o['paymentMethod'] != 'Credit' && tIntOrNull(o['cashAccountId']) == null) {
      trackerToast(context, 'Choose a cash account first', description: 'Pick the account this is paid from, then post.');
      await _review(o);
      return;
    }
    final id = tIntOrNull(o['occurrenceId']) ?? 0;
    setState(() => _busy = id);
    try {
      final r = await _api.post('/api/recurring-expenses/occurrences/$id/record?farmId=${Uri.encodeQueryComponent(_farmId)}', body: {});
      if (mounted) trackerToast(context, '${o['templateName']} posted', description: r is Map ? tStr(r['message']) : null);
      await _reload();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not post it', description: e.message, error: true);
      await _reloadOccurrences();
    }
    if (mounted) setState(() => _busy = null);
  }

  Future<void> _put(String path, Map<String, dynamic> body) =>
      _api.put('/api/recurring-expenses/$path?farmId=${Uri.encodeQueryComponent(_farmId)}', body: {...body, 'farmId': _farmId});

  Future<void> _review(Map o) async {
    final lk = _lookups;
    if (lk == null) return;
    final res = await showDialog<({bool andPost, Map saved})>(
      context: context,
      builder: (_) => _ReviewDialog(occurrence: o, lookups: lk, gh: _gh, save: (b) => _put('occurrences/${o['occurrenceId']}', b)),
    );
    if (res == null || !mounted) return;
    await _reloadOccurrences();
    if (res.andPost) await _post({...o, ...res.saved});
  }

  Future<void> _skip(Map o) async {
    final reason = await _prompt(
      title: 'Skip ${o['templateName']} (${recDay(o['scheduledDate'])})?',
      description: 'Nothing is recorded for this period. You can restore it later.',
      label: 'Why?',
      confirm: 'Skip',
    );
    if (reason == null) return;
    try {
      await _put('occurrences/${o['occurrenceId']}/skip', {'reason': reason});
      if (mounted) trackerToast(context, 'Skipped');
      await _reloadOccurrences();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not skip it', description: e.message, error: true);
    }
  }

  Future<void> _simple(String path, Map<String, dynamic> body, String ok, String fail) async {
    try {
      await _put(path, body);
      if (mounted) trackerToast(context, ok);
      await _reloadOccurrences();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, fail, description: e.message, error: true);
    }
  }

  Future<void> _link(Map o) async {
    final v = await _prompt(
      title: 'Link the expense that was recorded',
      description: 'Enter the expense number from the Expenses page, so this period is not recorded twice.',
      label: 'Expense number',
      confirm: 'Link',
      singleLine: true,
    );
    if (v == null) return;
    final id = int.tryParse(v.trim());
    if (id == null || id <= 0) {
      if (mounted) trackerToast(context, 'Enter the expense number', error: true);
      return;
    }
    await _simple('occurrences/${o['occurrenceId']}/link', {'expenseId': id}, 'Linked', 'Could not link it');
  }

  Future<void> _act(Map t, String action) async {
    try {
      await _put('templates/${t['templateId']}/status', {'action': action, 'reason': null});
      if (mounted) {
        trackerToast(context, action == 'Pause' ? 'Paused' : 'Resumed',
            description: action == 'Resume' ? 'It continues from today; periods missed while paused are not raised.' : null);
      }
      await _reload();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not ${action.toLowerCase()} it', description: e.message, error: true);
    }
  }

  Future<void> _end(Map t) async {
    final reason = await _prompt(
      title: 'End "${t['name']}"?',
      description: 'No more drafts will be raised. Drafts already waiting stay for review, and posted expenses are not touched.',
      label: 'Reason (optional)',
      confirm: 'End it',
      allowEmpty: true,
      destructive: true,
    );
    if (reason == null) return;
    try {
      await _put('templates/${t['templateId']}/status', {'action': 'End', 'reason': reason.isEmpty ? null : reason});
      if (mounted) trackerToast(context, 'Ended');
      await _reload();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not end it', description: e.message, error: true);
    }
  }

  Future<void> _delete(Map t) async {
    try {
      await _api.delete('/api/recurring-expenses/templates/${t['templateId']}?farmId=${Uri.encodeQueryComponent(_farmId)}');
      if (mounted) trackerToast(context, 'Deleted');
      await _reload();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not delete it', description: e.message, error: true);
    }
  }

  Future<void> _editor([Map? template]) async {
    final lk = _lookups;
    if (lk == null) return;
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => RecurringTemplateEditor(session: widget.session, company: widget.company, lookups: lk, template: template),
    ));
    if (saved != true) return;
    try {
      await _api.post('/api/recurring-expenses/generate?farmId=${Uri.encodeQueryComponent(_farmId)}', body: {});
    } on ApiException {
      // As the web.
    }
    await _reload();
  }

  /// PromptDialog: returns the text, or null when cancelled.
  Future<String?> _prompt({
    required String title,
    required String description,
    required String label,
    required String confirm,
    bool allowEmpty = false,
    bool singleLine = false,
    bool destructive = false,
  }) =>
      showDialog<String>(
        context: context,
        builder: (ctx) {
          final c = TextEditingController();
          return StatefulBuilder(
            builder: (ctx, set) => AlertDialog(
              scrollable: true,
              title: Text(title),
              content: SizedBox(
                width: 420,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(description, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                  const SizedBox(height: 12),
                  FilterLabel(
                    label,
                    AppInput(
                      controller: c,
                      minLines: singleLine ? 1 : 2,
                      maxLines: singleLine ? 1 : 4,
                      keyboardType: singleLine ? TextInputType.number : null,
                      onChanged: (_) => set(() {}),
                    ),
                  ),
                ]),
              ),
              actions: [
                OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(
                  style: destructive ? FilledButton.styleFrom(backgroundColor: TColors.red600) : null,
                  onPressed: !allowEmpty && c.text.trim().isEmpty ? null : () => Navigator.pop(ctx, c.text.trim()),
                  child: Text(confirm),
                ),
              ],
            ),
          );
        },
      );

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/recurring-expenses');
    final drafts = [for (final o in _occurrences) if (o['status'] == 'Draft' || o['status'] == 'Posting') o];
    final draftTotal = drafts.fold<num>(0, (s, o) => s + tNum(o['amount']));
    final upcomingTotal = _upcoming.fold<num>(0, (s, u) => s + tNum(u['amount']));

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Recurring Expenses')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.repeat, size: 22, color: Color(0xFF4F46E5)),
              SizedBox(width: 8),
              Expanded(child: Text('Recurring Expenses', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            const SizedBox(height: 4),
            const Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Rent, security, internet, software, waste collection — set it up once. When one falls due it waits here as a'),
                TextSpan(text: ' draft', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' for you to check and post; nothing is paid or recorded until you do.'),
              ]),
              style: TextStyle(fontSize: 13, color: TColors.slate600),
            ),
            if (_canWrite) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                onPressed: () => _editor(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New recurring expense'),
              ),
            ],
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _tile('Drafts to review', '${drafts.length}', amber: true)),
              const SizedBox(width: 10),
              Expanded(child: _tile('Drafts total', _gh(draftTotal), amber: true)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _tile('Due in next $_days days', '${_upcoming.length}')),
              const SizedBox(width: 10),
              Expanded(child: _tile('Expected', _gh(upcomingTotal))),
            ]),
            const SizedBox(height: 14),
            // The three tabs; they wrap rather than overflow a phone.
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final (v, l, ic) in [
                ('review', 'To review (${drafts.length})', Icons.inbox_outlined),
                ('upcoming', 'Upcoming', Icons.calendar_month_outlined),
                ('templates', 'Templates (${_templates.length})', Icons.repeat),
              ])
                ChoiceChip(
                  avatar: Icon(ic, size: 16),
                  label: Text(l),
                  selected: _tab == v,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _tab = v),
                ),
            ]),
            const SizedBox(height: 10),
            if (_tab == 'review')
              _pills('Show', [for (final (v, l) in occurrenceViews) (v, l)], _occView, (v) {
                setState(() => _occView = v);
                _reloadOccurrences();
              }),
            if (_tab == 'upcoming')
              _pills('Show', [('7', 'Next 7 days'), ('30', 'Next 30 days')], '$_days', (v) {
                setState(() => _days = int.parse(v));
                _reloadUpcoming();
              }),
            const SizedBox(height: 10),
            if (_tab == 'review') ..._reviewTab(),
            if (_tab == 'upcoming') ..._upcomingTab(),
            if (_tab == 'templates') ..._templatesTab(),
          ],
        ),
      ),
    );
  }

  Widget _tile(String label, String value, {bool amber = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: amber ? TColors.amber100 : TColors.blue100,
          border: Border.all(color: amber ? TColors.amber300 : TColors.blue300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 12, color: amber ? TColors.amber900 : TColors.blue900)),
          Text(value, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: amber ? TColors.amber900 : TColors.blue900)),
        ]),
      );

  Widget _pills(String label, List<(String, String)> options, String value, ValueChanged<String> on) => Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          for (final (v, l) in options)
            ChoiceChip(label: Text(l), selected: v == value, onSelected: (_) => on(v), visualDensity: VisualDensity.compact),
        ],
      );

  Widget _emptyCard(Widget child) => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
        child: Center(child: DefaultTextStyle.merge(style: const TextStyle(color: TColors.slate500), child: child)),
      );

  Widget _box(List<Widget> children, {double opacity = 1}) => Opacity(
        opacity: opacity,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      );

  static const _sm = TextStyle(fontSize: 12, color: TColors.slate500);

  List<Widget> _reviewTab() {
    if (_loading) return [const LoadingLine('Loading…')];
    if (_occurrences.isEmpty) {
      return [
        _emptyCard(_occView == 'Open'
            ? const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle_outline, size: 16, color: TColors.emerald600),
                SizedBox(width: 6),
                Text('Nothing waiting for review.'),
              ])
            : const Text('Nothing here.')),
      ];
    }
    return [for (final o in _occurrences) _occurrence(o)];
  }

  Widget _occurrence(Map o) {
    final status = tStr(o['status']);
    final draft = status == 'Draft';
    final interrupted = o['isInterrupted'] == true;
    final id = tIntOrNull(o['occurrenceId']);
    final (bg, fg, bd) = switch (status) {
      'Draft' => (TColors.amber100, TColors.amber800, TColors.amber300),
      'Posting' => (TColors.blue100, const Color(0xFF1E40AF), TColors.blue300),
      'Posted' => (TColors.emerald100, TColors.emerald800, TColors.emerald300),
      _ => (TColors.slate100, TColors.slate500, TColors.slate300),
    };
    final method = tStr(o['paymentMethod']);
    final cash = tIntOrNull(o['cashAccountId']);
    return _box([
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tStr(o['templateName']), style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
            Text(
              'Due ${recDay(o['scheduledDate'])} · ${tStr(o['categoryName']).isEmpty ? '—' : o['categoryName']}'
              '${tIntOrNull(o['supplierId']) != null ? ' · ${_supplierName(o['supplierId']) ?? 'supplier'}' : ''}',
              style: _sm,
            ),
          ]),
        ),
        const SizedBox(width: 8),
        // Narrow and wrapping: beside the name the estimate note overflows a phone.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 130),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_gh(tNum(o['amount'])), style: const TextStyle(fontWeight: FontWeight.w600)),
          if (o['isVariable'] == true && tNum(o['amount']) == tNum(o['templateAmount']) && draft)
            const Text('Estimate — confirm the actual amount', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: TColors.amber700)),
          if (tNum(o['amount']) != tNum(o['templateAmount']))
            Text('usually ${_gh(tNum(o['templateAmount']))}', style: const TextStyle(fontSize: 11, color: TColors.slate500)),
          ]),
        ),
      ]),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        TBadge(interrupted ? 'Posting interrupted' : status, bg: bg, fg: fg, border: bd),
        Text(
          '${method == 'Credit' ? 'On credit (will be owed)' : '$method${cash != null ? ' · ${_cashName(cash) ?? 'account'}' : ' · no cash account'}'}'
          ' · dated ${recDay(o['expenseDate'])}',
          style: _sm,
        ),
        if (status == 'Posted')
          Text('· expense #${o['expenseId']} by ${tStr(o['postedBy']).isEmpty ? '—' : o['postedBy']} '
              '${tStr(o['postedAt']).isNotEmpty ? fmtDateTimeLike(o['postedAt']) : ''}', style: _sm),
        if (status == 'Skipped') Text('· ${tStr(o['skipReason'])}', style: _sm),
      ]),
      if (tStr(o['note']).isNotEmpty) ...[const SizedBox(height: 4), Text(tStr(o['note']), style: const TextStyle(fontSize: 12, color: TColors.slate600))],
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 6, children: [
        if (draft && _canWrite)
          OutlinedButton.icon(onPressed: () => _review(o), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Review')),
        if (draft && _canWrite)
          FilledButton.icon(
            onPressed: _busy == id ? null : () => _post(o),
            icon: _busy == id
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('Post'),
          ),
        if (draft && _canWrite) TextButton.icon(onPressed: () => _skip(o), icon: const Icon(Icons.skip_next, size: 16), label: const Text('Skip')),
        if (status == 'Skipped' && _canWrite)
          OutlinedButton.icon(
            onPressed: () => _simple('occurrences/$id/restore', {}, 'Restored to draft', 'Could not restore it'),
            icon: const Icon(Icons.restore, size: 16),
            label: const Text('Restore'),
          ),
        if (interrupted && _canWrite) ...[
          OutlinedButton.icon(onPressed: () => _link(o), icon: const Icon(Icons.link_off, size: 16), label: const Text('It was recorded — link it')),
          OutlinedButton(
            onPressed: () => _simple('occurrences/$id/release', {'reason': 'Checked Expenses: not recorded'}, 'Back to draft', 'Could not release it'),
            child: const Text("It wasn't — back to draft"),
          ),
        ],
      ]),
      if (interrupted) ...[
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.warning_amber_rounded, size: 14, color: TColors.amber800),
          const SizedBox(width: 4),
          Expanded(
            child: Wrap(children: [
              Text('Posting started ${tStr(o['claimedAt']).isNotEmpty ? fmtDateTimeLike(o['claimedAt']) : ''} and never finished. Check ',
                  style: const TextStyle(fontSize: 12, color: TColors.amber800)),
              InkWell(
                onTap: () => openAppHref(context, widget.session, widget.company, _lookups?.expensesHref ?? '/expenses', label: 'Expenses'),
                child: const Text('Expenses',
                    style: TextStyle(fontSize: 12, color: TColors.amber800, decoration: TextDecoration.underline)),
              ),
              const Text(' for it before choosing.', style: TextStyle(fontSize: 12, color: TColors.amber800)),
            ]),
          ),
        ]),
      ],
    ]);
  }

  List<Widget> _upcomingTab() {
    if (_upcoming.isEmpty) return [_emptyCard(Text('Nothing falls due in the next $_days days.'))];
    return [
      for (final u in _upcoming)
        _box([
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tStr(u['name']), style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
                Text(
                  '${recDay(u['scheduledDate'])} · ${tIntOrNull(u['daysAway']) == 1 ? 'tomorrow' : 'in ${u['daysAway']} days'} · ${frequencyLabel(u['frequency'])}',
                  style: _sm,
                ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_gh(tNum(u['amount'])), style: const TextStyle(fontWeight: FontWeight.w600)),
              if (u['isVariable'] == true) const Text('estimate', style: TextStyle(fontSize: 11, color: TColors.slate500)),
            ]),
          ]),
        ]),
    ];
  }

  List<Widget> _templatesTab() {
    if (_templates.isEmpty) return [_emptyCard(const Text('No recurring expenses yet.'))];
    return [
      for (final t in _templates)
        () {
          final status = tStr(t['status']);
          final (bg, fg, bd) = switch (status) {
            'Active' => (TColors.emerald100, TColors.emerald800, TColors.emerald300),
            'Paused' => (TColors.amber100, TColors.amber800, TColors.amber300),
            _ => (TColors.slate100, TColors.slate500, TColors.slate300),
          };
          final used = tNum(t['posted']) + tNum(t['drafts']) + tNum(t['skipped']);
          return _box(opacity: status == 'Ended' ? .7 : 1, [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(tStr(t['name']), style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
                    TBadge(status, bg: bg, fg: fg, border: bd),
                    if (t['approvalMode'] == 'AutoPost') const TBadge('Posts automatically', bg: Colors.white, fg: TColors.slate700, border: TColors.slate200),
                  ]),
                  Text(
                    '${frequencyLabel(t['frequency'])} from ${recDay(t['startDate'])}${tStr(t['endDate']).isNotEmpty ? ' to ${recDay(t['endDate'])}' : ''}'
                    ' · ${tStr(t['categoryName']).isEmpty ? '—' : t['categoryName']}'
                    '${tStr(t['nextDueDate']).isNotEmpty && status == 'Active' ? ' · next ${recDay(t['nextDueDate'])}' : ''}',
                    style: _sm,
                  ),
                  Text(
                    '${t['posted'] ?? 0} posted · ${t['drafts'] ?? 0} waiting · ${t['skipped'] ?? 0} skipped'
                    '${tStr(t['endReason']).isNotEmpty ? ' · ended: ${t['endReason']}' : ''}',
                    style: _sm,
                  ),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_gh(tNum(t['amount'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                if (t['isVariable'] == true) const Text('varies', style: TextStyle(fontSize: 11, color: TColors.slate500)),
              ]),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              if (_canWrite && status != 'Ended')
                OutlinedButton.icon(onPressed: () => _editor(t), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
              if (_canWrite && status == 'Active')
                OutlinedButton.icon(onPressed: () => _act(t, 'Pause'), icon: const Icon(Icons.pause, size: 16), label: const Text('Pause')),
              if (_canWrite && status == 'Paused')
                OutlinedButton.icon(onPressed: () => _act(t, 'Resume'), icon: const Icon(Icons.play_arrow, size: 16), label: const Text('Resume')),
              if (_canWrite && status != 'Ended')
                TextButton.icon(onPressed: () => _end(t), icon: const Icon(Icons.stop, size: 16), label: const Text('End')),
              if (_canWrite && used == 0)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: TColors.rose600),
                  onPressed: () => _delete(t),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Delete'),
                ),
            ]),
          ]);
        }(),
    ];
  }
}

// ------------------------------------------------------------ template editor

/// "New recurring expense" / Edit "…". Pops true when saved.
class RecurringTemplateEditor extends StatefulWidget {
  const RecurringTemplateEditor({super.key, required this.session, required this.company, required this.lookups, this.template});
  final Session session;
  final Company company;
  final RecurringLookups lookups;
  final Map? template;

  @override
  State<RecurringTemplateEditor> createState() => _RecurringTemplateEditorState();
}

class _RecurringTemplateEditorState extends State<RecurringTemplateEditor> {
  late final Map? t = widget.template;
  late final _name = TextEditingController(text: tStr(t?['name']));
  late final _amount = TextEditingController(text: t == null ? '0' : tNum(t!['amount']).toString().replaceFirst(RegExp(r'\.0$'), ''));
  late final _desc = TextEditingController(text: tStr(t?['description']));
  late String? _category = tStr(t?['categoryName']).isEmpty ? null : tStr(t?['categoryName']);
  late int? _supplier = tIntOrNull(t?['supplierId']);
  late bool _variable = t?['isVariable'] == true;
  late String _frequency = tStr(t?['frequency']).isEmpty ? 'Monthly' : tStr(t?['frequency']);
  late String _start = t == null ? isoDay(DateTime.now().toUtc()) : recDay(t!['startDate']);
  late String _end = tStr(t?['endDate']).isEmpty ? '' : recDay(t!['endDate']);
  late String _method = tStr(t?['paymentMethod']).isEmpty ? 'Cash' : tStr(t?['paymentMethod']);
  late int? _cash = tIntOrNull(t?['cashAccountId']);
  late String _mode = t?['approvalMode'] == 'AutoPost' ? 'AutoPost' : 'Draft';
  List<String> _errors = [];
  bool _saving = false;
  FarmMoney _gh = const FarmMoney();

  bool get _frozen => t != null && tNum(t!['posted']) + tNum(t!['drafts']) + tNum(t!['skipped']) > 0;
  num get _amt => num.tryParse(_amount.text) ?? 0;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final errs = validateTemplate(
      name: _name.text,
      amount: _amt,
      frequency: _frequency,
      startDate: _start,
      endDate: _end.isEmpty ? null : _end,
      categoryOk: (_category ?? '').isNotEmpty,
      paymentMethod: _method,
      supplierId: _supplier,
      cashAccountId: _cash,
      approvalMode: _mode,
    );
    setState(() => _errors = errs);
    if (errs.isNotEmpty) return;
    setState(() => _saving = true);
    final farmId = widget.company.farmId;
    final body = {
      'name': _name.text,
      'categoryId': null,
      'categoryName': _category,
      'supplierId': _supplier,
      'payeeName': t?['payeeName'],
      'amount': _amt,
      'isVariable': _variable,
      'frequency': _frequency,
      'startDate': _start,
      'endDate': _end.isEmpty ? null : _end,
      'paymentMethod': _method,
      'cashAccountId': _cash,
      'description': _desc.text.isEmpty ? null : _desc.text,
      'approvalMode': _mode,
      'farmId': farmId,
    };
    final api = widget.session.farmClient;
    final q = '?farmId=${Uri.encodeQueryComponent(farmId)}';
    try {
      if (t != null) {
        await api.put('/api/recurring-expenses/templates/${t!['templateId']}$q', body: body);
      } else {
        await api.post('/api/recurring-expenses/templates$q', body: body);
      }
      if (!mounted) return;
      trackerToast(context, t != null ? 'Saved' : 'Recurring expense created');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        trackerToast(context, 'Could not save it', description: e.message, error: true);
      }
    }
  }

  Widget _field(String label, Widget child) => Padding(padding: const EdgeInsets.only(bottom: 12), child: FilterLabel(label, child));

  Widget _mode1(String v, String l, String h) => Expanded(
        child: InkWell(
          onTap: () => setState(() => _mode = v),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _mode == v ? const Color(0xFFEEF2FF) : null,
              border: Border.all(color: _mode == v ? const Color(0xFF6366F1) : TColors.slate200, width: _mode == v ? 1.5 : 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              Text(h, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final lk = widget.lookups;
    final dates = _start.isEmpty ? <String>[] : previewDates(_start, _frequency, 4, _end.isEmpty ? null : _end);
    return Scaffold(
      appBar: AppBar(title: Text(t != null ? 'Edit "${t!['name']}"' : 'New recurring expense')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          const Text('Each time it falls due, a draft waits for review — nothing is posted on its own unless you choose that below.',
              style: TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 14),
          _field('Name *', AppInput(controller: _name, hintText: 'e.g. Office rent')),
          _field(
            'Category *',
            AppSelect<String>(
              value: _category,
              hintText: 'Choose',
              items: [for (final c in lk.textCategories) AppSelectItem(value: c, label: c)],
              onChanged: (v) => setState(() => _category = v),
            ),
          ),
          _field(
            'Supplier / payee',
            AppSelect<int>(
              value: _supplier ?? 0,
              items: [
                const AppSelectItem(value: 0, label: 'No supplier'),
                for (final s in lk.suppliers) AppSelectItem(value: s.id, label: s.name),
              ],
              onChanged: (v) => setState(() => _supplier = v == null || v == 0 ? null : v),
            ),
          ),
          _field(
            'Amount *',
            AppInput(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
              onChanged: (_) => setState(() {}),
            ),
          ),
          _field(
            'Amount varies',
            Row(children: [
              Switch(value: _variable, onChanged: (v) => setState(() => _variable = v)),
              const SizedBox(width: 6),
              const Expanded(child: Text('Treat as an estimate (e.g. electricity)', style: TextStyle(fontSize: 13, color: TColors.slate600))),
            ]),
          ),
          _field(
            'Repeats *',
            AppSelect<String>(
              value: _frequency,
              enabled: !_frozen,
              items: [for (final (v, l) in recurringFrequencies) AppSelectItem(value: v, label: l)],
              onChanged: (v) => setState(() => _frequency = v ?? _frequency),
            ),
          ),
          _field(
            'First due date *',
            IgnorePointer(
              ignoring: _frozen,
              child: Opacity(
                opacity: _frozen ? .6 : 1,
                child: AppDateField(value: businessDateAsDateTime(_start), onChanged: (d) => setState(() => _start = d == null ? '' : isoDay(d))),
              ),
            ),
          ),
          _field('End date (optional)', AppDateField(value: businessDateAsDateTime(_end), onChanged: (d) => setState(() => _end = d == null ? '' : isoDay(d)))),
          _field(
            'Payment method',
            AppSelect<String>(
              value: _method,
              items: [for (final m in recurringPaymentMethods) AppSelectItem(value: m, label: recurringMethodLabel(m))],
              onChanged: (v) => setState(() => _method = v ?? _method),
            ),
          ),
          if (_method != 'Credit')
            _field(
              'Cash account',
              AppSelect<int>(
                value: _cash ?? 0,
                items: [
                  const AppSelectItem(value: 0, label: 'Choose when posting'),
                  for (final a in lk.cashAccounts) AppSelectItem(value: a.id, label: a.name),
                ],
                onChanged: (v) => setState(() => _cash = v == null || v == 0 ? null : v),
              ),
            ),
          _field(
            'When it falls due',
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _mode1('Draft', 'Draft for review (recommended)', 'Waits here; you check the amount and post it.'),
              const SizedBox(width: 8),
              _mode1('AutoPost', 'Post automatically', 'Recorded as soon as it falls due, with the default amount.'),
            ]),
          ),
          _field('Description', AppInput(controller: _desc, minLines: 2, maxLines: 4)),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Next dates: ', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: dates.isEmpty ? '—' : dates.join(' · ')),
              ]), style: const TextStyle(fontSize: 12, color: TColors.slate600)),
              Text(paymentEffect(_method, _cash != null, lk.moduleApproves), style: const TextStyle(fontSize: 12, color: TColors.slate600)),
              if (_amt > 0)
                Text('${_gh(_amt)} ${frequencyLabel(_frequency).toLowerCase()}${_variable ? ' (estimate)' : ''}.',
                    style: const TextStyle(fontSize: 12, color: TColors.slate600)),
              if (_frozen)
                const Text('Frequency and first date are fixed once a period has been raised — they define which period each one is.',
                    style: TextStyle(fontSize: 12, color: TColors.amber800)),
            ]),
          ),
          if (_errors.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFF1F2), border: Border.all(color: TColors.rose200), borderRadius: BorderRadius.circular(6)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final e in _errors) Text(e, style: const TextStyle(fontSize: 13, color: TColors.rose800)),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ review dialog

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({required this.occurrence, required this.lookups, required this.gh, required this.save});
  final Map occurrence;
  final RecurringLookups lookups;
  final FarmMoney gh;
  final Future<void> Function(Map<String, dynamic> body) save;
  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  Map get o => widget.occurrence;
  late final _amount = TextEditingController(text: tNum(o['amount']).toString().replaceFirst(RegExp(r'\.0$'), ''));
  late String _date = recDay(o['expenseDate']);
  late String _method = tStr(o['paymentMethod']).isEmpty ? 'Cash' : tStr(o['paymentMethod']);
  late int? _cash = tIntOrNull(o['cashAccountId']);
  late int? _supplier = tIntOrNull(o['supplierId']);
  late final _note = TextEditingController(text: tStr(o['note']));
  bool _saving = false;

  String? get _blocker => _method == 'Credit'
      ? (_supplier == null ? 'Choose the supplier it will be owed to.' : null)
      : (_cash == null ? 'Choose the cash account it is paid from.' : null);

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save(bool andPost) async {
    setState(() => _saving = true);
    final cash = _method == 'Credit' ? null : _cash;
    try {
      await widget.save({
        'amount': num.tryParse(_amount.text) ?? 0,
        'expenseDate': _date,
        'paymentMethod': _method,
        'cashAccountId': cash,
        'supplierId': _supplier,
        'note': _note.text.isEmpty ? null : _note.text,
      });
      if (mounted) Navigator.pop(context, (andPost: andPost, saved: {'paymentMethod': _method, 'cashAccountId': cash, 'supplierId': _supplier}));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        trackerToast(context, 'Could not save the draft', description: e.message, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lk = widget.lookups;
    final blocker = _blocker;
    return AlertDialog(
      scrollable: true,
      title: Text(tStr(o['templateName'])),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Due ${recDay(o['scheduledDate'])} · usually ${widget.gh(tNum(o['templateAmount']))}',
              style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 12),
          FilterLabel(
            'Actual amount *',
            AppInput(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
            ),
          ),
          const SizedBox(height: 10),
          FilterLabel('Expense date *', AppDateField(value: businessDateAsDateTime(_date), onChanged: (d) => setState(() => _date = d == null ? '' : isoDay(d)))),
          const SizedBox(height: 10),
          FilterLabel(
            'Payment method',
            AppSelect<String>(
              value: _method,
              items: [for (final m in recurringPaymentMethods) AppSelectItem(value: m, label: recurringMethodLabel(m))],
              onChanged: (v) => setState(() => _method = v ?? _method),
            ),
          ),
          const SizedBox(height: 10),
          if (_method != 'Credit')
            FilterLabel(
              'Cash account',
              AppSelect<int>(
                value: _cash,
                hintText: 'Choose',
                items: [for (final a in lk.cashAccounts) AppSelectItem(value: a.id, label: a.name)],
                onChanged: (v) => setState(() => _cash = v),
              ),
            )
          else
            FilterLabel(
              'Supplier *',
              AppSelect<int>(
                value: _supplier,
                hintText: 'Choose',
                items: [for (final s in lk.suppliers) AppSelectItem(value: s.id, label: s.name)],
                onChanged: (v) => setState(() => _supplier = v),
              ),
            ),
          const SizedBox(height: 10),
          FilterLabel('Note', AppInput(controller: _note, hintText: 'e.g. meter reading 4,512')),
          const SizedBox(height: 8),
          Text(blocker ?? paymentEffect(_method, _cash != null, lk.moduleApproves),
              style: TextStyle(fontSize: 12, color: blocker == null ? TColors.slate500 : TColors.amber700)),
        ]),
      ),
      actions: [
        OutlinedButton(onPressed: _saving ? null : () => _save(false), child: const Text('Save draft')),
        FilledButton(onPressed: _saving || blocker != null ? null : () => _save(true), child: Text(_saving ? 'Saving…' : 'Save and post')),
      ],
    );
  }
}
