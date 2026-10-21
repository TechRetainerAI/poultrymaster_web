// Restaurant → Money → Reconciliation, as `app/restaurant-cash-reconciliation/page.tsx`:
// a count is saved as a Draft first, and posting it — the only step that
// moves money — is separate (migration 338). Cash boxes, banks and wallets are
// counted here; tills are counted when their shift closes on Tills & Shifts.
// The history shows both kinds together, drafts included.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart';
import '../poultry/reports/report_format.dart' show FarmMoney;
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart' show CompactPager, LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/reason_select.dart' show cashCountReversalReasons;
import 'restaurant_cash_accounts_screen.dart' show restaurantAccountTypeLabels;
import 'restaurant_money_kit.dart';
import 'restaurant_roles.dart' show restaurantRose;
import 'restaurant_widgets.dart';

typedef ReconHistoryRow = ({
  String key,
  String date,
  String kind,
  String account,
  String reference,
  num system,
  num counted,
  num difference,
  String by,
  String note,
  String status,
  int? countId,
});

String _d10(Object? s) => tStr(s).length >= 10 ? tStr(s).substring(0, 10) : tStr(s);

/// Counts in [from]..[to] and the closed till shifts, newest first.
List<ReconHistoryRow> reconciliationHistory(List<Map> counts, List<Map> shifts, String from, String to) {
  final rows = <ReconHistoryRow>[
    for (final c in counts)
      if (_d10(c['countDate']).compareTo(from) >= 0 && _d10(c['countDate']).compareTo(to) <= 0)
        (
          key: 'c${c['countId']}',
          date: _d10(c['countDate']),
          kind: 'Count',
          account: tStr(c['accountName']),
          reference: 'Count #${tIntOrNull(c['countId'])}',
          system: tNum(c['systemBalance']),
          counted: tNum(c['countedBalance']),
          difference: tNum(c['difference']),
          by: tStr(c['createdBy']),
          note: c['status'] == 'Reversed' ? 'Reversed: ${tStr(c['reversalReason'])}' : tStr(c['notes']),
          status: tStr(c['status']),
          countId: tIntOrNull(c['countId']),
        ),
    for (final s in shifts)
      (
        key: 's${s['shiftId']}',
        date: _d10(tStr(s['closedAt']).isNotEmpty ? s['closedAt'] : s['openedAt']),
        kind: 'Till shift',
        account: tStr(s['tillName']),
        reference: tStr(s['shiftNumber']),
        system: tNum(s['expectedCash']),
        counted: tNum(s['countedCash']),
        difference: tNum(s['variance']),
        by: tStr(s['closedBy']),
        note: tStr(s['closeNotes']),
        status: 'Posted',
        countId: null,
      ),
  ];
  rows.sort((a, b) => b.date.compareTo(a.date));
  return rows;
}

const _countBadge = {
  'Draft': (TColors.slate100, TColors.slate700),
  'Posted': (Color(0xFFDCFCE7), Color(0xFF15803D)),
  'Reversed': (Color(0xFFFEF3C7), TColors.amber700),
};

Widget _statusBadge(String s) {
  final (bg, fg) = _countBadge[s] ?? (Colors.white, TColors.slate500);
  return rStatusBadge(s, bg: bg, fg: fg, border: bg);
}

class RestaurantCashReconciliationScreen extends StatefulWidget {
  const RestaurantCashReconciliationScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantCashReconciliationScreen> createState() => _RestaurantCashReconciliationScreenState();
}

class _RestaurantCashReconciliationScreenState extends State<RestaurantCashReconciliationScreen> {
  bool _loading = true;
  List<Map> _accounts = [], _counts = [], _shifts = [];
  String _from = '${rTodayIso().substring(0, 8)}01';
  String _to = rTodayIso();
  String? _accountId;
  final _counted = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;
  int? _editingDraftId;
  int _page = 1, _pageSize = 10;
  FarmMoney _gh = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  bool get _canView => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    if (_canView) {
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _counted.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        loadRestaurantAccounts(_api, _farmId),
        _api.get(rFin('/counts', _farmId)),
        _api.get(rFin('/shifts', _farmId, {'status': 'Closed', 'from': _from, 'to': _to})),
      ]);
      if (!mounted) return;
      setState(() {
        _accounts = r[0] as List<Map>;
        _counts = rowsOf(r[1]);
        _shifts = rowsOf(r[2]);
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load reconciliation', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _go(String href, String label) => openAppHref(context, widget.session, widget.company, href, label: label);

  // Tills are reconciled by closing their shift, so they are not offered here.
  List<Map> get _countable => [for (final a in _accounts) if (a['isActive'] == true && a['accountType'] != 'Till') a];
  Map? get _chosen => _countable.where((a) => '${tIntOrNull(a['cashAccountId'])}' == _accountId).firstOrNull;
  Map? get _accountDraft {
    final c = _chosen;
    if (c == null) return null;
    return _counts.where((x) => x['cashAccountId'] == c['cashAccountId'] && x['status'] == 'Draft').firstOrNull;
  }

  bool get _formLocked => _accountDraft != null && _editingDraftId != tIntOrNull(_accountDraft!['countId']);
  num get _countedValue => num.tryParse(_counted.text.trim()) ?? 0;

  void _startEditDraft(int id) {
    final c = _counts.where((x) => tIntOrNull(x['countId']) == id).firstOrNull;
    if (c == null) return;
    setState(() {
      _accountId = '${tIntOrNull(c['cashAccountId'])}';
      final v = tNum(c['countedBalance']);
      _counted.text = v == v.roundToDouble() ? v.toInt().toString() : '$v';
      _notes.text = tStr(c['notes']);
      _editingDraftId = id;
    });
  }

  void _cancelEdit() => setState(() {
        _editingDraftId = null;
        _counted.clear();
        _notes.clear();
      });

  /// Saves only. Posting is a separate step.
  Future<void> _saveDraft() async {
    final chosen = _chosen;
    if (chosen == null || _counted.text.isEmpty) return;
    setState(() => _saving = true);
    final notes = _notes.text.isEmpty ? null : _notes.text;
    try {
      if (_editingDraftId != null) {
        await _api.put(rFin('/counts/$_editingDraftId/draft', _farmId), body: {'counted': _countedValue, 'notes': notes});
        if (mounted) trackerToast(context, 'Draft updated');
      } else {
        await _api.post(rFin('/counts/draft', _farmId),
            body: {'cashAccountId': tIntOrNull(chosen['cashAccountId']), 'counted': _countedValue, 'notes': notes});
        if (mounted) trackerToast(context, 'Draft saved', description: 'Nothing has been posted yet -- post it below to move the money.');
      }
      _cancelEdit();
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not save the draft', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  /// The only thing on this page that moves money.
  Future<void> _postDraft(int id) async {
    setState(() => _saving = true);
    try {
      final res = await _api.post(rFin('/counts/$id/post', _farmId));
      final adjusted = res is Map && res['adjustmentTransactionId'] != null;
      if (mounted) {
        trackerToast(context, adjusted ? 'Cash count posted' : 'Balanced',
            description: adjusted
                ? 'The difference has been posted to the ledger as an adjustment.'
                : 'The count matched the ledger, so no adjustment was needed.');
      }
      if (_editingDraftId == id) _cancelEdit();
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, "Couldn't post the count", description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _discard(int id) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => RConfirmDialog(
        title: 'Discard count #$id?',
        description: 'Nothing was posted, so no money moves and nothing is reversed. The draft is removed and the account can be counted again.',
        confirmLabel: 'Discard draft',
        errorTitle: 'Could not discard the draft',
        onConfirm: () => _api.delete(rFin('/counts/$id/draft', _farmId)),
      ),
    );
    if (done == true) {
      if (_editingDraftId == id) _cancelEdit();
      _load();
    }
  }

  Future<void> _reverse(ReconHistoryRow h) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => RReasonDialog(
        title: 'Reverse this count?',
        description: 'The over / short it posted is taken back out, dated today. The count stays on record as reversed.',
        options: cashCountReversalReasons,
        keepLabel: 'Cancel',
        confirmLabel: 'Reverse',
        busyLabel: 'Reverse',
        errorTitle: 'Could not reverse',
        destructive: false,
        submit: (reason) => _api.post(rFin('/counts/${h.countId}/reverse', _farmId), body: {'reason': reason}),
      ),
    );
    if (done == true) {
      if (mounted) trackerToast(context, 'Count reversed');
      _load();
    }
  }

  List<Widget> _actions(ReconHistoryRow h) {
    if (h.kind != 'Count') return [];
    if (h.status == 'Draft') {
      return [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: TColors.emerald700, side: const BorderSide(color: TColors.emerald200)),
          onPressed: _saving ? null : () => _postDraft(h.countId!),
          icon: const Icon(Icons.check, size: 16),
          label: const Text('Post'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: TColors.rose700, side: const BorderSide(color: TColors.rose200)),
          onPressed: () => _startEditDraft(h.countId!),
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: const Text('Edit'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: Color(0xFFFECACA))),
          onPressed: () => _discard(h.countId!),
          icon: const Icon(Icons.delete_outline, size: 16),
          label: const Text('Discard'),
        ),
      ];
    }
    if (h.status == 'Posted') return [OutlinedButton(onPressed: () => _reverse(h), child: const Text('Reverse'))];
    return [];
  }

  Widget _accTile(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: .4, color: TColors.slate500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-cash-reconciliation');
    Widget body;
    if (!_canView) {
      body = const TCard(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Text('You do not have access to Reconciliation.', style: TextStyle(color: TColors.slate600))),
        ),
      );
    } else if (_loading) {
      body = const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: LoadingLine('Loading…')));
    } else {
      final history = reconciliationHistory(_counts, _shifts, _from, _to);
      final live = [for (final h in history) if (h.status == 'Posted') h];
      final short = -live.where((h) => h.difference < 0).fold<num>(0, (t, h) => t + h.difference);
      final over = live.where((h) => h.difference > 0).fold<num>(0, (t, h) => t + h.difference);
      final chosen = _chosen;
      final draft = _accountDraft;
      final locked = _formLocked;
      final diff = chosen != null && _counted.text.isNotEmpty ? rRound2(_countedValue - tNum(chosen['currentBalance'])) : 0;
      if ((_page - 1) * _pageSize >= history.length && _page > 1) _page = 1;
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RPageHeader(
          icon: Icons.balance,
          title: 'Reconciliation',
          subtitle: 'Count the cash box, confirm the bank and wallet balances, see every over and short',
          actions: [
            OutlinedButton(onPressed: () => _go('/restaurant-cash-accounts', 'Cash Account'), child: const Text('Back to Cash Accounts')),
          ],
        ),
        const SizedBox(height: 14),
        twoColumns([
          MoneyStat(label: 'Short this period', value: _gh(short), accent: 'rose'),
          MoneyStat(label: 'Over this period', value: _gh(over), accent: 'amber'),
          MoneyStat(label: 'Checks that balanced', value: '${live.where((h) => h.difference == 0).length} of ${live.length}', accent: 'emerald'),
        ]),
        const SizedBox(height: 14),
        TCard(
          title: 'Record a count',
          descriptionSpans: [
            const TextSpan(
                text: 'Count the cash, or read the balance off the bank or mobile-money statement, then save it as a draft — saving does not move money, you post it after. Tills are counted when you close their shift on '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: () => _go('/restaurant-tills', 'Tills & Shifts'),
                child: const Text('Tills & Shifts', style: TextStyle(fontSize: 13, color: TColors.slate500, decoration: TextDecoration.underline)),
              ),
            ),
            const TextSpan(text: '.'),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (chosen != null) ...[
              twoColumns([
                _accTile('System balance', _gh(tNum(chosen['currentBalance']))),
                _accTile('Last counted', tStr(chosen['lastCountedAt']).isNotEmpty ? _d10(chosen['lastCountedAt']) : 'Never'),
                _accTile('Counted then', chosen['lastCountedBalance'] != null ? _gh(tNum(chosen['lastCountedBalance'])) : '—'),
              ], gap: 8),
              const SizedBox(height: 12),
            ],
            if (draft != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: TColors.rose50, border: Border.all(color: TColors.rose200), borderRadius: BorderRadius.circular(8)),
                child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: TColors.rose700),
                  Text(
                    'Count #${tIntOrNull(draft['countId'])} is saved but not posted — nothing has reached the ledger yet. Counted ${_gh(tNum(draft['countedBalance']))}.',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF881337)),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: restaurantRose, visualDensity: VisualDensity.compact),
                    onPressed: _saving ? null : () => _postDraft(tIntOrNull(draft['countId'])!),
                    child: const Text('Post it'),
                  ),
                  if (_editingDraftId != tIntOrNull(draft['countId']))
                    OutlinedButton(
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () => _startEditDraft(tIntOrNull(draft['countId'])!),
                        child: const Text('Edit')),
                  OutlinedButton(
                      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => _discard(tIntOrNull(draft['countId'])!),
                      child: const Text('Discard')),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            if (_editingDraftId != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: const Color(0xFFF0F9FF), border: Border.all(color: const Color(0xFFBAE6FD)), borderRadius: BorderRadius.circular(8)),
                child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('Editing draft count #$_editingDraftId. Saving updates it — posting is still a separate step.',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF0C4A6E))),
                  TextButton(onPressed: _cancelEdit, child: const Text('Cancel edit')),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            rField(
              'Account',
              AppSelect<String>(
                value: _accountId,
                hintText: 'Choose an account',
                enabled: _editingDraftId == null,
                items: [
                  for (final a in _countable)
                    AppSelectItem(
                        value: '${tIntOrNull(a['cashAccountId'])}',
                        label: '${tStr(a['name'])} (${restaurantAccountTypeLabels[tStr(a['accountType'])] ?? tStr(a['accountType'])})'),
                ],
                onChanged: (v) => setState(() {
                  _accountId = v;
                  _counted.clear();
                  _notes.clear();
                }),
              ),
            ),
            const SizedBox(height: 12),
            rField('System says', rFigureBox('', chosen != null ? _gh(tNum(chosen['currentBalance'])) : '—')),
            const SizedBox(height: 12),
            rField(
              'Counted / statement balance',
              AppInput(
                controller: _counted,
                enabled: chosen != null && !locked,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (chosen != null && _counted.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: diff == 0 ? const Color(0xFFF0FDF4) : diff > 0 ? TColors.amber50 : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  diff == 0
                      ? 'It balances.'
                      : '${diff > 0 ? 'Over' : 'Short'} by ${_gh(diff.abs())} — saved as a draft; posting it moves cash ${diff > 0 ? 'in' : 'out'}.',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: diff == 0 ? const Color(0xFF166534) : diff > 0 ? const Color(0xFF92400E) : const Color(0xFF991B1B)),
                ),
              ),
            ],
            const SizedBox(height: 12),
            AppInput(
              controller: _notes,
              enabled: chosen != null && !locked,
              hintText: diff < 0 ? 'Why is it short?' : 'Notes (optional)',
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: restaurantRose),
              onPressed: chosen == null || _counted.text.isEmpty || _saving || locked ? null : _saveDraft,
              icon: _saving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const SizedBox.shrink(),
              label: Text(_editingDraftId != null ? 'Update draft' : 'Save draft'),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        TCard(
          title: 'Reconciliation history',
          description: 'Account counts and till cash-ups together.',
          headerExtra: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.end, children: [
              SizedBox(width: 150, child: rDateInput(_from, (v) {
                setState(() => _from = v);
                _load();
              })),
              SizedBox(width: 150, child: rDateInput(_to, (v) {
                setState(() => _to = v);
                _load();
              })),
              OutlinedButton(onPressed: _load, child: const Text('Show')),
            ]),
          ),
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
          child: history.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No counts or cash-ups in this period.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate500)),
                )
              : MobileCardList<ReconHistoryRow>(
                  items: pageSlice(history, _page, _pageSize),
                  striped: true,
                  keyOf: (h) => h.key,
                  primary: (h) => h.account,
                  secondary: (h) => '${h.date} · ${h.kind}${h.reference.isNotEmpty ? ' · ${h.reference}' : ''}',
                  trailing: (h) => h.status != 'Posted' ? _statusBadge(h.status) : null,
                  highlights: (h) => [
                    Highlight(h.difference < 0 ? 'Short' : h.difference > 0 ? 'Over' : 'Balanced', _gh(h.difference),
                        accent: h.difference < 0 ? Accent.rose : h.difference > 0 ? Accent.amber : Accent.emerald,
                        wide: true,
                        strike: h.status == 'Reversed'),
                    Highlight('System', _gh(h.system)),
                    Highlight('Counted', _gh(h.counted), accent: Accent.blue),
                  ],
                  details: (h) => [('By', h.by.isEmpty ? '—' : h.by), ('Note', h.note.isEmpty ? '—' : h.note)],
                  actions: _actions,
                  table: (rows) => TrackerTable(
                    columns: const [
                      TCol('Date', width: 95),
                      TCol('Type', width: 150),
                      TCol('Account', width: 130),
                      TCol('Reference', width: 110),
                      TCol('System', right: true, width: 105),
                      TCol('Counted', right: true, width: 105),
                      TCol('Over / short', right: true, width: 110),
                      TCol('By', width: 100),
                      TCol('Note', width: 160),
                      TCol('', right: true, width: 330),
                    ],
                    rows: [
                      for (final h in rows)
                        () {
                          final grey = h.status == 'Reversed' ? TColors.slate400 : null;
                          return [
                            cellText(h.date, color: grey),
                            Wrap(spacing: 4, runSpacing: 4, children: [
                              rStatusBadge(h.kind),
                              if (h.status != 'Posted') _statusBadge(h.status),
                            ]),
                            cellText(h.account, color: grey, bold: true),
                            cellText(h.reference, color: grey),
                            cellText(_gh(h.system), color: grey),
                            cellText(_gh(h.counted), color: grey),
                            Text(_gh(h.difference),
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  decoration: h.status == 'Reversed' ? TextDecoration.lineThrough : null,
                                  color: h.status == 'Reversed'
                                      ? TColors.slate400
                                      : h.difference < 0
                                          ? TColors.red600
                                          : h.difference > 0
                                              ? const Color(0xFFD97706)
                                              : const Color(0xFF15803D),
                                )),
                            cellText(h.by, color: grey),
                            cellText(h.note, color: grey),
                            Wrap(alignment: WrapAlignment.end, spacing: 6, runSpacing: 6, children: _actions(h)),
                          ];
                        }(),
                    ],
                  ),
                  pager: CompactPager(
                    total: history.length,
                    page: _page,
                    pageSize: _pageSize,
                    onPage: (p) => setState(() => _page = p),
                    onPageSize: (v) => setState(() {
                      _pageSize = v;
                      _page = 1;
                    }),
                  ),
                ),
        ),
      ]);
    }
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Reconciliation')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [body]),
      ),
    );
  }
}
