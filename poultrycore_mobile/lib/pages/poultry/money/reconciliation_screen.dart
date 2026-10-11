import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../reports/report_format.dart';
import '../sales/balances_logic.dart' show pageSlice;
import '../sales/balances_widgets.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';
import 'cash_account_dialogs.dart' show cashReasons;
import 'cash_accounts_screen.dart' show CashAccountDetailScreen, CashAccountsScreen;
import 'cash_vocabulary.dart';
import 'money_widgets.dart';

/// Poultry → Money → Reconciliation, as `app/poultry-cash-reconciliation/page.tsx`:
/// check what an account actually holds against what the system says. A count
/// is saved as a draft, then posted; the difference becomes an adjustment.

/// POULTRY_CASH_REVERSAL_REASONS — why a posted count should never have been.
const cashReversalReasons = [
  'Counted the wrong account', 'Miscounted', 'Wrong amount entered', 'Wrong date', 'Duplicate count',
  'Posted by mistake', 'Cash located afterwards', 'Test or training entry', 'Other',
];

const _sky600 = Color(0xFF0284C7);

/// COUNT_BADGE: (bg, fg).
(Color, Color) countTone(String s) => switch (s) {
      'Posted' => (const Color(0xFFDCFCE7), const Color(0xFF15803D)),
      'Reversed' => (TColors.amber100, TColors.amber700),
      _ => (TColors.slate100, TColors.slate700),
    };

String countRef(Map c) => tStr(c['referenceNo']).isNotEmpty ? tStr(c['referenceNo']) : '#${tStr(c['poultryCashReconciliationId'])}';

/// The account the page opens on: the asked-for one if it exists, else the
/// first active, else the first.
int? initialReconcileAccount(List<Map> accounts, int? wanted) {
  if (wanted != null && wanted != 0 && accounts.any((a) => tIntOrNull(a['poultryCashAccountId']) == wanted)) return wanted;
  final active = accounts.where((a) => a['isActive'] == true).firstOrNull;
  return tIntOrNull((active ?? accounts.firstOrNull)?['poultryCashAccountId']);
}

/// The count form's arithmetic: difference to the cent, balanced within 0.01.
({num difference, bool balanced}) countDifference(num counted, num system) {
  final d = ((counted - system) * 100).round() / 100;
  return (difference: d, balanced: d.abs() < 0.01);
}

class ReconciliationScreen extends StatefulWidget {
  const ReconciliationScreen({super.key, required this.session, required this.company, this.accountId, this.fromAccounts = false});
  final Session session;
  final Company company;

  /// `?accountId=` — the account to open on.
  final int? accountId;

  /// Opened from the Cash Account list, so Back returns to it.
  final bool fromAccounts;

  @override
  State<ReconciliationScreen> createState() => _ReconciliationScreenState();
}

class _ReconciliationScreenState extends State<ReconciliationScreen> {
  List<Map> _accounts = [], _status = [], _counts = [];
  int? _accountId;
  bool _loading = true, _busy = false;
  String _error = '';
  int _page = 1, _pageSize = 10, _lastTotal = -1;
  FarmMoney _gh = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _first();
  }

  Future<void> _first() async {
    final accs = await _loadAccounts();
    if (!mounted) return;
    setState(() {
      _accountId ??= initialReconcileAccount(accs, widget.accountId);
      _loading = false;
    });
    await _loadCounts();
  }

  /// Accounts and the status feed, settled separately.
  Future<List<Map>> _loadAccounts() async {
    setState(() => _error = '');
    List<Map> accs = [];
    try {
      accs = rowsOf(await _api.get('/api/Poultry/cash-accounts', query: {'farmId': _farmId}));
      if (mounted) setState(() => _accounts = accs);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    try {
      final st = rowsOf(await _api.get('/api/Poultry/cash-reconciliations/account-status', query: {'farmId': _farmId}));
      if (mounted) setState(() => _status = st);
    } on ApiException {
      if (mounted) setState(() => _status = []);
    }
    return accs;
  }

  Future<void> _loadCounts() async {
    final id = _accountId;
    if (id == null) return setState(() => _counts = []);
    try {
      final c = rowsOf(await _api.get('/api/Poultry/cash-reconciliations/account/$id', query: {'farmId': _farmId}));
      if (mounted && id == _accountId) setState(() => _counts = c);
    } on ApiException {
      if (mounted) setState(() => _counts = []);
    }
  }

  Future<void> _refreshAll() async {
    await _loadAccounts();
    await _loadCounts();
  }

  Map? get _account => _accounts.where((a) => tIntOrNull(a['poultryCashAccountId']) == _accountId).firstOrNull;
  Map? get _accountStatus => _status.where((s) => tIntOrNull(s['poultryCashAccountId']) == _accountId).firstOrNull;
  num get _systemBalance => tNum(_accountStatus?['ledgerBalance'] ?? _account?['currentBalance']);
  Map? get _openDraft => _counts.where((c) => tStr(c['status']) == 'Draft').firstOrNull;
  CashVocabulary get _vocab => cashAccountVocabulary(_account?['accountType']);

  Future<void> _postDraft(Map c) async {
    setState(() => _busy = true);
    try {
      final res = await _api.post('/api/Poultry/cash-reconciliations/${tStr(c['poultryCashReconciliationId'])}/post',
          query: {'farmId': _farmId}, body: {'clearedTransactionIds': <int>[], 'postedBy': widget.session.tokens.userId});
      final adj = res is Map ? res['adjustmentTransactionId'] : null;
      if (mounted) {
        trackerToast(context, adj != null ? 'Cash count posted' : 'Balanced',
            description: adj != null
                ? 'The difference has been posted to the ledger as an adjustment.'
                : 'The count matched the ledger, so no adjustment was needed.');
      }
      await _refreshAll();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, "Couldn't post the count", description: e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _recalculate() async {
    setState(() => _busy = true);
    try {
      await _api.post('/api/Poultry/cash-accounts/reconcile-balances', query: {'farmId': _farmId});
      if (mounted) trackerToast(context, 'Balances recalculated', description: "Every cash account's balance was rebuilt from its transactions.");
      await _refreshAll();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Recalculate failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  /// The count form: a new count, a draft being corrected, or a copy of a reversed one.
  Future<void> _openForm({Map? count, String? mode}) async {
    final acc = _account;
    if (acc == null) return;
    final draft = _openDraft;
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => CashCountDialog(
        session: widget.session,
        company: widget.company,
        account: acc,
        vocab: _vocab,
        systemBalance: _systemBalance,
        fmt: _gh,
        editing: count,
        mode: mode,
        disabled: draft != null && tStr(count?['poultryCashReconciliationId']) != tStr(draft['poultryCashReconciliationId']),
      ),
    );
    if (done == true) _refreshAll();
  }

  void _reconcile() {
    final d = _openDraft;
    d == null ? _openForm() : _openForm(count: d, mode: 'draft');
  }

  Future<void> _discard(Map c) async {
    final ok = await confirmDelete(context,
        title: 'Discard ${tStr(c['referenceNo']).isEmpty ? 'this draft' : tStr(c['referenceNo'])}?',
        description:
            'Nothing was posted, so no money moves and nothing is reversed. The draft is removed and the account can be counted again.',
        confirmLabel: 'Discard draft');
    if (!ok) return;
    try {
      await _api.delete('/api/Poultry/cash-reconciliations/${tStr(c['poultryCashReconciliationId'])}'
          '?farmId=${Uri.encodeQueryComponent(_farmId)}&userId=${Uri.encodeQueryComponent(widget.session.tokens.userId ?? '')}');
      await _refreshAll();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not discard the draft', description: e.message, error: true);
    }
  }

  Future<void> _reverse(Map c) async {
    final reason = await showDialog<String>(context: context, builder: (_) => const ReasonPromptDialog());
    if (reason == null) return;
    try {
      await _api.post('/api/Poultry/cash-reconciliations/${tStr(c['poultryCashReconciliationId'])}/reverse',
          query: {'farmId': _farmId}, body: {'reason': reason, 'reversedBy': widget.session.tokens.userId});
      if (mounted) trackerToast(context, 'Cash count reversed', description: 'The adjustment has been undone.');
      await _refreshAll();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, "Couldn't reverse", description: e.message, error: true);
    }
  }

  Widget _tile(String label, String value, {String? hint}) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          if (hint != null) Text(hint, style: const TextStyle(fontSize: 10, color: TColors.slate500)),
        ]),
      );

  Widget _banner(Color bg, Color border, Color fg, Widget child) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(child: child),
        ]),
      );

  Widget _small(String label, VoidCallback? on, {bool filled = false}) => filled
      ? FilledButton(onPressed: on, style: FilledButton.styleFrom(visualDensity: VisualDensity.compact), child: Text(label))
      : OutlinedButton(
          onPressed: on, style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, backgroundColor: Colors.white), child: Text(label));

  Widget _action(String label, IconData icon, Color color, Color border, VoidCallback? on) => OutlinedButton.icon(
        onPressed: on,
        style: OutlinedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: color, side: BorderSide(color: border)),
        icon: Icon(icon, size: 16),
        label: Text(label),
      );

  List<Widget> _countActions(Map c) => [
        if (tStr(c['status']) == 'Draft') ...[
          _action('Post', Icons.check, TColors.emerald700, const Color(0xFFA7F3D0), _busy ? null : () => _postDraft(c)),
          _action('Edit', Icons.edit_outlined, TColors.sky700, const Color(0xFFBAE6FD), () => _openForm(count: c, mode: 'draft')),
          _action('Discard', Icons.delete_outline, TColors.rose600, const Color(0xFFFECDD3), () => _discard(c)),
        ],
        if (tStr(c['status']) == 'Posted')
          _action('Reverse', Icons.undo, TColors.amber700, const Color(0xFFFDE68A), () => _reverse(c)),
        if (tStr(c['status']) == 'Reversed')
          _action('Count again', Icons.replay, TColors.sky700, const Color(0xFFBAE6FD), () => _openForm(count: c, mode: 'copy')),
      ];

  String _diff(Map c) => tNum(c['difference']) == 0 ? 'Balanced' : _gh(tNum(c['difference']));

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-cash-reconciliation');
    final acc = _account;
    final st = _accountStatus;
    final draft = _openDraft;
    final vocab = _vocab;
    final drift = tNum(st?['cacheDrift']);
    final hasDrift = drift.abs() >= 0.01;
    if (_counts.length != _lastTotal) {
      _lastTotal = _counts.length;
      _page = 1;
    }
    final pageRows = pageSlice(_counts, _page, _pageSize);

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Reconciliation')),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => widget.fromAccounts
                    ? Navigator.of(context).pop()
                    : Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => CashAccountsScreen(session: widget.session, company: widget.company))),
                style: TextButton.styleFrom(foregroundColor: TColors.slate600, padding: EdgeInsets.zero),
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('Back to Cash & Accounts'),
              ),
            ),
            const Row(children: [
              Icon(Icons.balance, size: 20, color: _sky600),
              SizedBox(width: 8),
              Expanded(child: Text('Reconciliation', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Check what an account actually holds against what the system says. The difference is posted as an adjustment — balances are never edited directly.',
              style: TextStyle(fontSize: 12, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_accounts.isNotEmpty) ...[
                  const Text('ACCOUNT TO RECONCILE',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4, color: TColors.slate500)),
                  const SizedBox(height: 4),
                  AppSelect<String>(
                    value: _accountId == null ? null : '$_accountId',
                    hintText: 'Pick an account to reconcile',
                    items: [
                      for (final a in _accounts)
                        AppSelectItem(
                          value: tStr(a['poultryCashAccountId']),
                          label: '${tStr(a['accountName'])}${a['isActive'] == true ? '' : ' (inactive)'}',
                        ),
                    ],
                    onChanged: (v) {
                      final id = int.tryParse(v ?? '');
                      if (id == null || id == _accountId) return;
                      setState(() {
                        _accountId = id;
                        _counts = [];
                      });
                      _loadCounts();
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                LayoutBuilder(builder: (context, c) {
                  final half = (c.maxWidth - 8) / 2;
                  return Wrap(spacing: 8, runSpacing: 8, children: [
                    if (acc != null)
                      SizedBox(
                        width: half,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => CashAccountDetailScreen(
                                session: widget.session, company: widget.company, accountId: tIntOrNull(acc['poultryCashAccountId']) ?? 0),
                          )),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Open ledger'),
                        ),
                      ),
                    SizedBox(
                      width: half,
                      child: OutlinedButton.icon(
                        onPressed: _busy || _loading ? null : _recalculate,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Recalculate'),
                      ),
                    ),
                    if (acc != null)
                      SizedBox(
                        width: c.maxWidth,
                        child: FilledButton.icon(
                          onPressed: _reconcile,
                          icon: const Icon(Icons.balance, size: 16),
                          label: Text(draft != null
                              ? 'Finish ${tStr(draft['referenceNo']).isNotEmpty ? tStr(draft['referenceNo']) : vocab.recordNoun}'
                              : vocab.action),
                        ),
                      ),
                  ]);
                }),
              ]),
            ),
            const SizedBox(height: 8),
            if (_error.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFFECACA)), borderRadius: BorderRadius.circular(8)),
                child: Text(_error, style: const TextStyle(color: Color(0xFFB91C1C))),
              ),
              const SizedBox(height: 8),
            ],
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(40), child: Center(child: Text('Loading cash accounts…', style: TextStyle(color: TColors.slate600))))
            else if (_accounts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                    child: Text('No cash accounts yet. Create one under Cash accounts first.',
                        textAlign: TextAlign.center, style: TextStyle(color: TColors.slate600))),
              )
            else if (acc != null) ...[
              twoUp([
                _tile('System balance', _gh(_systemBalance), hint: hasDrift ? 'rebuilt from transactions' : null),
                _tile('Last counted', st?['lastReconciledAt'] != null ? tStr(st!['lastReconciledAt']).split('T').first : 'Never',
                    hint: st?['daysSinceReconciled'] != null ? '${tStr(st!['daysSinceReconciled'])} days ago' : null),
                _tile('Counted then', st?['lastReconciledBalance'] != null ? _gh(tNum(st!['lastReconciledBalance'])) : '—'),
                _tile('Uncleared entries', st != null ? tStr(st['unclearedCount']).isEmpty ? '0' : tStr(st['unclearedCount']) : '—',
                    hint: st != null && tNum(st['unclearedCount']) > 0 ? _gh(tNum(st['unclearedAmount'])) : null),
              ]),
              if (hasDrift) ...[
                const SizedBox(height: 8),
                _banner(
                  TColors.amber50,
                  const Color(0xFFFDE68A),
                  TColors.amber700,
                  Text(
                    'The stored balance for this account is ${_gh(drift.abs())} away from what its transactions add up to. The reconciliation uses the transactions, so it is safe to post — but other screens will show the stale figure until you recalculate.',
                    style: const TextStyle(fontSize: 12, color: TColors.amber900),
                  ),
                ),
              ],
              if (draft != null) ...[
                const SizedBox(height: 8),
                _banner(
                  const Color(0xFFF0F9FF),
                  const Color(0xFFBAE6FD),
                  TColors.sky700,
                  Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(
                      '${countRef(draft)} is saved but not posted — nothing has reached the ledger yet.'
                      '${draft['actualBalance'] != null ? ' Counted ${_gh(tNum(draft['actualBalance']))}.' : ''}',
                      style: const TextStyle(fontSize: 12, color: TColors.sky900),
                    ),
                    _small('Post it', _busy ? null : () => _postDraft(draft), filled: true),
                    _small('Edit', () => _openForm(count: draft, mode: 'draft')),
                    _small('Discard', () => _discard(draft)),
                  ]),
                ),
              ],
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Reconciliation History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const Text('Reversing one posts an opposite adjustment — the original is kept.',
                      style: TextStyle(fontSize: 12, color: TColors.slate500)),
                  const SizedBox(height: 10),
                  if (_counts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(vocab.emptyHistory, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                    )
                  else
                    MobileCardList<Map>(
                      striped: true,
                      stripeBlue: true,
                      items: pageRows,
                      keyOf: (c) => tStr(c['poultryCashReconciliationId']),
                      primary: countRef,
                      secondary: (c) => fmtDateTime(c['reconciliationDate'], c, _offset),
                      trailing: (c) {
                        final (bg, fg) = countTone(tStr(c['status']));
                        return Padding(padding: const EdgeInsets.only(left: 6), child: TBadge(tStr(c['status']), bg: bg, fg: fg));
                      },
                      highlights: (c) => [
                        Highlight('System', _gh(tNum(c['systemBalance']))),
                        Highlight('Counted', c['actualBalance'] != null ? _gh(tNum(c['actualBalance'])) : '—', accent: Accent.violet),
                        Highlight('Difference', _diff(c), accent: tNum(c['difference']) < 0 ? Accent.rose : Accent.emerald, wide: true),
                      ],
                      details: (c) => [('Reason', tStr(c['reason']).isEmpty ? '—' : tStr(c['reason']))],
                      actions: _countActions,
                      table: (items) => TrackerTable(
                        columns: const [
                          TCol('Reference', width: 120),
                          TCol('Date', width: 140),
                          TCol('System', right: true, width: 120),
                          TCol('Actual Balance', right: true, width: 130),
                          TCol('Difference', right: true, width: 120),
                          TCol('Reason', width: 150),
                          TCol('Status', width: 100),
                          TCol('Actions', right: true, width: 140),
                        ],
                        rows: [
                          for (final c in items)
                            () {
                              final d = tNum(c['difference']);
                              final (bg, fg) = countTone(tStr(c['status']));
                              Widget icon(String tip, IconData i, Color col, VoidCallback? on) =>
                                  IconButton(tooltip: tip, onPressed: on, icon: Icon(i, size: 18, color: col));
                              return <Widget>[
                                Text(countRef(c), style: const TextStyle(fontWeight: FontWeight.w500)),
                                cellText(fmtDateTime(c['reconciliationDate'], c, _offset)),
                                Align(alignment: Alignment.centerRight, child: Text(_gh(tNum(c['systemBalance'])))),
                                Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(c['actualBalance'] != null ? _gh(tNum(c['actualBalance'])) : '—')),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(_diff(c),
                                      style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: d == 0 ? TColors.slate500 : d > 0 ? TColors.emerald700 : const Color(0xFFBE123C))),
                                ),
                                Text(tStr(c['reason']).isEmpty ? '—' : tStr(c['reason']), style: const TextStyle(color: TColors.slate600)),
                                Align(alignment: Alignment.centerLeft, child: TBadge(tStr(c['status']), bg: bg, fg: fg)),
                                Wrap(alignment: WrapAlignment.end, children: [
                                  if (tStr(c['status']) == 'Draft') ...[
                                    icon('Post this count to the ledger', Icons.check, TColors.emerald600, _busy ? null : () => _postDraft(c)),
                                    icon('Edit this count', Icons.edit_outlined, const Color(0xFF0284C7), () => _openForm(count: c, mode: 'draft')),
                                    icon('Discard this draft', Icons.delete_outline, TColors.rose600, () => _discard(c)),
                                  ],
                                  if (tStr(c['status']) == 'Posted') icon('Reverse this count', Icons.undo, TColors.amber600, () => _reverse(c)),
                                  if (tStr(c['status']) == 'Reversed')
                                    icon('Count again from this one', Icons.replay, const Color(0xFF0284C7), () => _openForm(count: c, mode: 'copy')),
                                ]),
                              ];
                            }(),
                        ],
                      ),
                      pager: CompactPager(
                        total: _counts.length,
                        page: _page,
                        pageSize: _pageSize,
                        onPage: (p) => setState(() => _page = p),
                        onPageSize: (v) => setState(() {
                          _pageSize = v;
                          _page = 1;
                        }),
                      ),
                    ),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The reconciliation form (CashCountForm, intent "draft"), in its dialog.
class CashCountDialog extends StatefulWidget {
  const CashCountDialog({
    super.key,
    required this.session,
    required this.company,
    required this.account,
    required this.vocab,
    required this.systemBalance,
    required this.fmt,
    this.editing,
    this.mode,
    this.disabled = false,
  });
  final Session session;
  final Company company;
  final Map account;
  final CashVocabulary vocab;
  final num systemBalance;
  final FarmMoney fmt;

  /// The count being corrected ("draft") or copied ("copy"); null for a new one.
  final Map? editing;
  final String? mode;

  /// Another draft is open for this account (one open draft per account).
  final bool disabled;

  @override
  State<CashCountDialog> createState() => _CashCountDialogState();
}

class _CashCountDialogState extends State<CashCountDialog> {
  final _actual = TextEditingController();
  final _note = TextEditingController();
  final _notes = TextEditingController();
  String _reason = '';
  String _when = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      final a = e['actualBalance'];
      if (a != null) {
        final n = tNum(a);
        _actual.text = n == n.roundToDouble() ? n.toInt().toString() : '$n';
      }
      final stored = tStr(e['reason']);
      final known = cashReasons.contains(stored);
      _reason = stored.isEmpty ? '' : (known ? stored : 'Other');
      _note.text = stored.isNotEmpty && !known ? stored : '';
      _notes.text = tStr(e['notes']);
      if (widget.mode == 'draft' && tStr(e['reconciliationDate']).isNotEmpty) _when = tStr(e['reconciliationDate']).split('T').first;
    }
  }

  @override
  void dispose() {
    for (final c in [_actual, _note, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  num? get _value => num.tryParse(_actual.text);
  bool get _entered => _value != null;
  ({num difference, bool balanced}) get _d => countDifference(_value ?? 0, widget.systemBalance);
  bool get _reasonRequired => _entered && !_d.balanced;
  bool get _needsNote => _reason == 'Other';
  bool get _canSubmit =>
      _entered && !_saving && !widget.disabled && (!_reasonRequired || (_reason.isNotEmpty && (!_needsNote || _note.text.trim().isNotEmpty)));

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _saving = true);
    final v = widget.vocab;
    final d = _d;
    final fields = {
      'reconciliationDate': _when,
      'actualBalance': _value,
      'reason': _reason.isEmpty ? null : (_needsNote ? _note.text.trim() : _reason),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'createdBy': widget.session.tokens.userId,
    };
    final api = widget.session.farmClient;
    final q = {'farmId': widget.company.farmId};
    try {
      if (widget.mode == 'draft' && widget.editing != null) {
        await api.put(
            '/api/Poultry/cash-reconciliations/${tStr(widget.editing!['poultryCashReconciliationId'])}?farmId=${Uri.encodeQueryComponent(widget.company.farmId)}',
            body: fields);
      } else {
        await api.post('/api/Poultry/cash-reconciliations',
            query: q, body: {'poultryCashAccountId': tIntOrNull(widget.account['poultryCashAccountId']), ...fields});
      }
      if (!mounted) return;
      trackerToast(context, '${v.recordNounTitle} saved',
          description: d.balanced
              ? 'The ${v.balanceTerm.toLowerCase()} matches the system as things stand. Post it to confirm — nothing has moved yet.'
              : 'Post it to move ${widget.fmt(d.difference.abs())} ${d.difference > 0 ? 'in' : 'out'}. Nothing has moved yet.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, "Couldn't save the ${v.recordNoun}", description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vocab;
    final fmt = widget.fmt;
    final e = widget.editing;
    final d = _d;
    final off = widget.disabled;
    final title = widget.mode == 'draft'
        ? 'Edit ${tStr(e?['referenceNo']).isNotEmpty ? tStr(e?['referenceNo']) : v.recordNoun}'
        : widget.mode == 'copy'
            ? '${v.action} again'
            : v.action;
    final desc = widget.mode == 'draft'
        ? 'Correct the figures. The saved record is updated, not duplicated — posting is a separate step.'
        : widget.mode == 'copy'
            ? 'Seeded from ${tStr(e?['referenceNo']).isNotEmpty ? tStr(e?['referenceNo']) : 'the reversed record'}. This saves a new one; the reversed one stays in the history.'
            : '${tStr(widget.account['accountName'])} — saving does not move money. You post it after.';
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Row(children: [
          const Icon(Icons.balance, color: _sky600),
          const SizedBox(width: 6),
          Flexible(child: Text(title)),
        ]),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(desc, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            formSection(v.action, _sky600, [
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilterLabel(
                  '${v.amountLabel} *',
                  AppInput(
                    controller: _actual,
                    enabled: !off,
                    hintText: '0.00',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*'))],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 4),
                Text(v.helper, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilterLabel(
                  'System balance',
                  Container(
                    height: 44,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
                    child: Text(fmt(widget.systemBalance), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
                  ),
                ),
                if (_entered)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      d.balanced
                          ? 'Balanced — no adjustment needed'
                          : 'Difference: ${fmt(d.difference)} ${d.difference > 0 ? '(over)' : '(short)'}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: d.balanced ? TColors.emerald700 : TColors.amber700),
                    ),
                  ),
              ]),
              FilterLabel(
                'Date checked *',
                AppDateField(
                  enabled: !off,
                  value: businessDateAsDateTime(_when),
                  onChanged: (dt) => setState(() => _when = dt == null ? _when : isoDay(dt)),
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilterLabel(
                  _reasonRequired ? 'Reason *' : 'Reason',
                  AppSelect<String>(
                    value: _reason.isEmpty ? null : _reason,
                    enabled: !off,
                    hintText: d.balanced ? 'Not needed' : 'Why the difference?',
                    items: [for (final r in cashReasons) AppSelectItem(value: r, label: r)],
                    onChanged: (r) => setState(() {
                      _reason = r ?? '';
                      _note.clear();
                    }),
                  ),
                ),
                if (_needsNote) ...[
                  const SizedBox(height: 8),
                  AppInput(controller: _note, enabled: !off, autofocus: true, hintText: 'Say what happened', onChanged: (_) => setState(() {})),
                ],
              ]),
            ]),
            const SizedBox(height: 12),
            formSection('Notes', TColors.slate600, [
              FilterLabel('Notes (optional)',
                  AppInput(controller: _notes, enabled: !off, minLines: 2, maxLines: 4, hintText: 'Anything that explains the ${v.recordNoun}')),
            ]),
            if (_entered) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
                child: Text(
                  d.balanced
                      ? 'No adjustment will be created. The ${v.recordNoun} is recorded as balanced.'
                      : 'A ${d.difference > 0 ? 'money-in' : 'money-out'} adjustment of ${fmt(d.difference.abs())} will be posted to this account. The original transactions are untouched, and the ${v.recordNoun} can be reversed.',
                  style: const TextStyle(fontSize: 11.5, color: TColors.slate600),
                ),
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: _canSubmit ? _submit : null, child: Text(_saving ? 'Saving…' : 'Save ${v.recordNoun}')),
        ],
      ),
    );
  }
}

/// PromptDialog with the reversal-reason list: a pick is required, and "Other"
/// opens a box that must be filled. Pops the reason.
class ReasonPromptDialog extends StatefulWidget {
  const ReasonPromptDialog({
    super.key,
    this.title = 'Reverse this cash count?',
    this.description =
        'An opposite adjustment is posted, the original entries are kept, and anything this count marked as cleared goes back to uncleared.',
    this.placeholder = 'Why is this count being reversed?',
    this.options,
  });
  final String title, description;

  /// The select's placeholder (the web's PromptDialog defaults to "Select a reason").
  final String placeholder;

  /// (value, label) pairs; the cash-count reversal reasons when null.
  final List<(String, String)>? options;

  @override
  State<ReasonPromptDialog> createState() => _ReasonPromptDialogState();
}

class _ReasonPromptDialogState extends State<ReasonPromptDialog> {
  String _choice = '';
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    if (_choice.isEmpty) return setState(() => _error = 'Reason for reversal is required.');
    if (_choice != 'Other') return Navigator.pop(context, _choice);
    final t = _text.text.trim();
    if (t.isEmpty) return setState(() => _error = 'Reason for reversal is required.');
    Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(widget.title),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.description, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            FilterLabel(
              'Reason for reversal',
              AppSelect<String>(
                value: _choice.isEmpty ? null : _choice,
                hintText: widget.placeholder,
                items: [
                  for (final (v, l) in widget.options ?? [for (final r in cashReversalReasons) (r, r)]) AppSelectItem(value: v, label: l),
                ],
                onChanged: (v) => setState(() {
                  _choice = v ?? '';
                  _error = null;
                }),
              ),
            ),
            if (_choice == 'Other') ...[
              const SizedBox(height: 8),
              AppInput(controller: _text, autofocus: true, minLines: 4, maxLines: 6, hintText: 'Say what happened'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: const TextStyle(fontSize: 13, color: Color(0xFFBE123C))),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: _submit,
            style: FilledButton.styleFrom(backgroundColor: TColors.red600, foregroundColor: Colors.white),
            child: const Text('Reverse'),
          ),
        ],
      );
}
