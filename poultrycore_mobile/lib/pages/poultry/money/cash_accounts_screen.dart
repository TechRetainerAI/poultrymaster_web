import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../reports/report_format.dart';
import '../reports/report_routes.dart' show openAppHref;
import '../sales/balances_logic.dart' show pageSlice;
import '../sales/balances_widgets.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';
import 'cash_account_dialogs.dart';
import 'money_widgets.dart';
import 'reconciliation_screen.dart';

/// Poultry → Money → Cash Account, as `app/poultry-cash-accounts/page.tsx`
/// (list) and `[id]/page.tsx` (one account's ledger).

const _ledgerTypeLabels = {
  'CashIn': 'Money in',
  'CashOut': 'Money out',
  'TransferIn': 'Transfer in',
  'TransferOut': 'Transfer out',
  'TransferReversalIn': 'Transfer reversal in',
  'TransferReversalOut': 'Transfer reversal out',
  'AdjustmentIn': 'Adjustment in',
  'AdjustmentOut': 'Adjustment out',
  'OwnerContribution': 'Owner contribution',
  'OwnerDraw': 'Owner draw',
  'OwnerContributionReversal': 'Owner contribution reversed',
  'OwnerDrawReversal': 'Owner draw reversed',
  'LoanReceived': 'Loan received',
  'LoanReceivedReversal': 'Loan receipt reversed',
  'LoanRepayment': 'Loan repayment',
  'LoanRepaymentReversal': 'Loan repayment reversed',
};

/// ledgerTypeLabel: known types by name, a new one title-cased.
String ledgerTypeLabel(Object? raw) {
  final s = tStr(raw).trim();
  if (s.isEmpty) return '—';
  return _ledgerTypeLabels[s] ??
      s.replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}').replaceFirstMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase());
}

/// cashByAccount's attention rule for one status row: drift first, then
/// never reconciled, then more than 30 days since.
String? accountAttention(Map s) {
  if (tNum(s['cacheDrift']).abs() >= 0.01) return 'Stored balance disagrees with its transactions';
  if (s['lastReconciledAt'] == null) return 'Never reconciled';
  final days = tIntOrNull(s['daysSinceReconciled']) ?? 0;
  if (days > 30) return 'Not reconciled in $days days';
  return null;
}

/// Total cash at hand: active accounts, the LEDGER balance where the status
/// feed has it, else the cached balance.
num totalCashAtHand(List<Map> accounts, Map<String, Map> statusById) => accounts
    .where((a) => a['isActive'] == true)
    .fold<num>(0, (s, a) => s + tNum(statusById[tStr(a['poultryCashAccountId'])]?['ledgerBalance'] ?? a['currentBalance']));

/// The account ledger, oldest-first by day then id, with the running balance
/// from the opening balance; returned newest first.
List<Map> accountLedger(List<Map> rows, num opening) {
  String day(Map r) => tStr(r['transactionDate']).split('T').first;
  final asc = [...rows]..sort((a, b) {
      final d = day(a).compareTo(day(b));
      return d != 0 ? d : (tIntOrNull(a['poultryCashTransactionId']) ?? 0).compareTo(tIntOrNull(b['poultryCashTransactionId']) ?? 0);
    });
  var bal = opening;
  final out = [
    for (final r in asc) {...r, 'running': bal += tNum(r['amount'])},
  ];
  return out.reversed.toList();
}

const _sky600 = Color(0xFF0284C7);

class CashAccountsScreen extends StatefulWidget {
  const CashAccountsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<CashAccountsScreen> createState() => _CashAccountsScreenState();
}

class _CashAccountsScreenState extends State<CashAccountsScreen> {
  List<Map> _accounts = [], _transfers = [], _status = [];
  bool _loading = true, _saving = false;
  final _search = TextEditingController();
  int _page = 1, _pageSize = 10, _lastTotal = -1;
  FarmMoney _fmt = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _fmt = m);
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
    try {
      final q = {'farmId': _farmId};
      final r = await Future.wait([_api.get('/api/Poultry/cash-accounts', query: q), _api.get('/api/Poultry/cash-transfers', query: q)]);
      if (!mounted) return;
      setState(() {
        _accounts = rowsOf(r[0]);
        _transfers = rowsOf(r[1]);
      });
      // The status feed may not exist on an older database; the page still renders.
      List<Map> st = [];
      try {
        st = rowsOf(await _api.get('/api/Poultry/cash-reconciliations/account-status', query: q));
      } on ApiException {
        st = [];
      }
      if (mounted) setState(() => _status = st);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load cash accounts', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _dialog(Widget d) async {
    final done = await showDialog<bool>(context: context, builder: (_) => d);
    if (done == true) _load();
  }

  Future<void> _createDefault() async {
    const name = 'Main Cash Account';
    if (_accounts.any((a) => tStr(a['accountName']).trim().toLowerCase() == name.toLowerCase())) {
      return trackerToast(context, 'Default account already exists', description: '"$name" is already set up.');
    }
    setState(() => _saving = true);
    try {
      await _api.post('/api/Poultry/cash-accounts', body: {
        'accountName': name,
        'accountType': 'FarmCashBox',
        'openingBalance': 0,
        'allowNegativeBalance': false,
        'notes': 'Default cash account',
        'farmId': _farmId,
      });
      if (mounted) trackerToast(context, 'Default account created', description: '"$name" is ready to use.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not create default account', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _recalculate() async {
    try {
      await _api.post('/api/Poultry/cash-accounts/reconcile-balances', query: {'farmId': _farmId});
      if (mounted) trackerToast(context, 'Balances recalculated');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Recalculate failed', description: e.message, error: true);
    }
  }

  Future<void> _delete(Map a) async {
    final ok = await confirmDelete(context,
        title: 'Remove ${tStr(a['accountName']).isEmpty ? 'this account' : tStr(a['accountName'])}?',
        description: 'The account is deactivated so its transaction history stays intact.',
        confirmLabel: 'Remove account');
    if (!ok) return;
    try {
      await _api.delete('/api/Poultry/cash-accounts/${tStr(a['poultryCashAccountId'])}?farmId=${Uri.encodeQueryComponent(_farmId)}');
      if (mounted) trackerToast(context, 'Cash account removed');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not remove account', description: e.message, error: true);
    }
  }

  Future<void> _transferAction(Map t, String action) async {
    final id = tStr(t['poultryCashTransferId']);
    await _api.post('/api/Poultry/cash-transfers/$id/$action', query: {
      'farmId': _farmId,
      if (action == 'approve') 'approvedBy': widget.session.tokens.userId ?? '',
    });
    await _load();
  }

  void _href(String href, String label) => openAppHref(context, widget.session, widget.company, href, label: label);

  Future<void> _reconcile(int? accountId) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReconciliationScreen(session: widget.session, company: widget.company, accountId: accountId, fromAccounts: true),
    ));
    _load();
  }

  Future<void> _details(Map a) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CashAccountDetailScreen(
        session: widget.session,
        company: widget.company,
        accountId: tIntOrNull(a['poultryCashAccountId']) ?? 0,
        fromList: true,
      ),
    ));
    _load();
  }

  Future<void> _quickTransactions(Map a) async {
    List<Map>? rows;
    final sheet = showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        if (rows == null) {
          _api.get('/api/Poultry/cash-accounts/transactions', query: {'farmId': _farmId, 'cashAccountId': tStr(a['poultryCashAccountId'])}).then(
            (r) => set(() => rows = rowsOf(r)),
            onError: (Object e) {
              set(() => rows = []);
              if (mounted) trackerToast(context, 'Failed to load transactions', description: e is ApiException ? e.message : '$e', error: true);
            },
          );
        }
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: .8,
          builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
            Text('Transactions — ${tStr(a['accountName'])}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            if (rows == null || rows!.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('No transactions yet.', style: TextStyle(color: TColors.slate500)))
            else
              TrackerTable(
                columns: const [TCol('Date', width: 140), TCol('Type', width: 140), TCol('Source', width: 120), TCol('Amount', right: true, width: 120), TCol('Description', width: 220)],
                rows: [
                  for (final r in rows!)
                    [
                      cellText(fmtDateTime(r['transactionDate'], r, _offset)),
                      cellText(ledgerTypeLabel(r['transactionType'])),
                      cellText(tStr(r['sourceType']).isEmpty ? '—' : tStr(r['sourceType'])),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(_fmt(tNum(r['amount'])),
                            style: TextStyle(color: tNum(r['amount']) < 0 ? TColors.rose600 : const Color(0xFF15803D))),
                      ),
                      Text(tStr(r['description']).isEmpty ? '—' : tStr(r['description'])),
                    ],
                ],
              ),
          ]),
        );
      }),
    );
    await sheet;
  }

  Widget _statCard(String label, String value, Accent accent) {
    final (bg, border, lc, vc) = accentTone(accent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4, color: lc)),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: vc)),
      ]),
    );
  }

  Widget _activeBadge(Map a) => a['isActive'] == true
      ? const TBadge('Active', bg: Color(0xFFDCFCE7), fg: Color(0xFF15803D))
      : const TBadge('Inactive', bg: Colors.white, fg: TColors.slate700, border: TColors.slate300);

  Widget _accountsTable(List<Map> items, Map<String, Map> statusById) => TrackerTable(
        columns: const [
          TCol('Name', width: 150),
          TCol('Type', width: 120),
          TCol('Opening', right: true, width: 120),
          TCol('Current', right: true, width: 120),
          TCol('Calculated', right: true, width: 160),
          TCol('Reconciled', width: 170),
          TCol('Status', width: 90),
          TCol('Actions', right: true, width: 300),
        ],
        rows: [
          for (final a in items)
            () {
              final s = statusById[tStr(a['poultryCashAccountId'])];
              final reason = s == null ? null : accountAttention(s);
              final cur = tNum(a['currentBalance']);
              Widget act(String label, VoidCallback on, {Color? color}) => TextButton(
                    onPressed: on,
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: color),
                    child: Text(label),
                  );
              return <Widget>[
                Text(tStr(a['accountName']), style: const TextStyle(fontWeight: FontWeight.w500)),
                cellText(tStr(a['accountType'])),
                Align(alignment: Alignment.centerRight, child: Text(_fmt(tNum(a['openingBalance'])))),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(_fmt(cur), style: TextStyle(color: cur < 0 ? TColors.rose600 : TColors.slate500)),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: s == null
                      ? const Text('—', style: TextStyle(color: TColors.slate400))
                      : Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Text(_fmt(tNum(s['ledgerBalance'])),
                              style: TextStyle(fontWeight: FontWeight.w600, color: tNum(s['ledgerBalance']) < 0 ? TColors.rose600 : null)),
                          if (tNum(s['cacheDrift']).abs() >= 0.01)
                            Tooltip(
                              message: 'Stored balance is ${_fmt(tNum(s['cacheDrift']).abs())} away from this',
                              triggerMode: TooltipTriggerMode.tap,
                              child: const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Text('drift', style: TextStyle(fontSize: 10, color: TColors.amber700)),
                              ),
                            ),
                        ]),
                ),
                s == null
                    ? const Text('—', style: TextStyle(color: TColors.slate400))
                    : reason != null
                        ? Text(reason, style: const TextStyle(fontSize: 12, color: TColors.amber700))
                        : Text('${tStr(s['daysSinceReconciled'])}d ago', style: const TextStyle(fontSize: 12, color: TColors.emerald700)),
                Align(alignment: Alignment.centerLeft, child: _activeBadge(a)),
                Wrap(alignment: WrapAlignment.end, children: [
                  IconButton(tooltip: 'View details', onPressed: () => _details(a), icon: const Icon(Icons.visibility_outlined, size: 18)),
                  Tooltip(message: 'Quick transactions', child: act('Txns', () => _quickTransactions(a))),
                  act('Reconcile', () => _reconcile(tIntOrNull(a['poultryCashAccountId']))),
                  act('Edit', () => _dialog(CashAccountFormDialog(session: widget.session, company: widget.company, editing: a))),
                  IconButton(tooltip: 'Delete account', onPressed: () => _delete(a), icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444))),
                ]),
              ];
            }(),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-cash-accounts');
    final q = _search.text.trim().toLowerCase();
    final visible = q.isEmpty
        ? _accounts
        : [for (final a in _accounts) if ('${tStr(a['accountName'])}\u0000${tStr(a['accountType'])}'.toLowerCase().contains(q)) a];
    if (visible.length != _lastTotal) {
      _lastTotal = visible.length;
      _page = 1;
    }
    final pageRows = pageSlice(visible, _page, _pageSize);
    final statusById = {for (final s in _status) tStr(s['poultryCashAccountId']): s};
    final recent = _transfers.take(8).toList();

    Widget headerButton(IconData icon, String label, VoidCallback? on) => OutlinedButton.icon(
          onPressed: on,
          icon: Icon(icon, size: 16),
          label: Text(label),
        );

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Cash Account')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.account_balance_wallet_outlined, size: 24, color: _sky600),
              SizedBox(width: 8),
              Expanded(child: Text('Cash Account', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              headerButton(Icons.balance, 'Record Cash Adjustment',
                  () => _dialog(RecordCashAdjustmentDialog(session: widget.session, company: widget.company, accounts: _accounts, fmt: _fmt))),
              headerButton(Icons.refresh, 'Recalculate', _recalculate),
              headerButton(Icons.balance, 'Reconcile', () => _reconcile(null)),
              headerButton(Icons.description_outlined, 'Cash Account Report', () => _href('/poultry/reports/cash-accounts', 'Cash Account Report')),
              headerButton(Icons.swap_horiz, 'Transfer',
                  () => _dialog(CashTransferQuickDialog(session: widget.session, company: widget.company, accounts: _accounts))),
              headerButton(Icons.account_balance_wallet_outlined, 'Create default account', _saving ? null : _createDefault),
              FilledButton.icon(
                onPressed: () => _dialog(CashAccountFormDialog(session: widget.session, company: widget.company)),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New account'),
              ),
            ]),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _href('/cash-flow', 'Cash Flow'),
                style: TextButton.styleFrom(foregroundColor: _sky600, padding: EdgeInsets.zero),
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: const Text("See the whole company's cash flow →"),
              ),
            ),
            const SizedBox(height: 8),
            twoUp([
              _statCard('Total cash at hand', _fmt(totalCashAtHand(_accounts, statusById)), Accent.violet),
              _statCard('Active accounts', '${_accounts.where((a) => a['isActive'] == true).length}', Accent.emerald),
              _statCard('Pending transfers', '${_transfers.where((t) => tStr(t['status']) == 'Draft').length}', Accent.amber),
              _statCard('Approved transfers', '${_transfers.where((t) => tStr(t['status']) == 'Approved').length}', Accent.blue),
            ]),
            const SizedBox(height: 12),
            ListFiltersCard(
              search: _search,
              searchPlaceholder: 'Search account name or type',
              searchOnly: true,
              onSearch: () => setState(() {}),
              from: '',
              to: '',
              onDates: (_, _) {},
              onClear: () => setState(_search.clear),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Row(children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Loading…', style: TextStyle(color: TColors.slate500)),
              ])
            else if (_accounts.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  const Text('No cash accounts yet.', style: TextStyle(color: TColors.slate500)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _saving ? null : _createDefault,
                    icon: const Icon(Icons.account_balance_wallet_outlined, size: 16),
                    label: const Text('Create default account'),
                  ),
                ]),
              )
            else
              MobileCardList<Map>(
                striped: true,
                items: pageRows,
                keyOf: (a) => tStr(a['poultryCashAccountId']),
                primary: (a) => tStr(a['accountName']),
                secondary: (a) => tStr(a['accountType']),
                trailing: (a) => Padding(padding: const EdgeInsets.only(left: 6), child: _activeBadge(a)),
                highlights: (a) => [
                  Highlight('Opening', _fmt(tNum(a['openingBalance'])), accent: Accent.blue),
                  Highlight('Current', _fmt(tNum(a['currentBalance'])), accent: tNum(a['currentBalance']) < 0 ? Accent.rose : Accent.emerald),
                ],
                details: (a) => [('Type', tStr(a['accountType'])), ('Status', a['isActive'] == true ? 'Active' : 'Inactive')],
                actions: (a) => [
                  OutlinedButton.icon(onPressed: () => _details(a), icon: const Icon(Icons.visibility_outlined, size: 16), label: const Text('View details')),
                  OutlinedButton(
                    onPressed: () => _dialog(CashAccountFormDialog(session: widget.session, company: widget.company, editing: a)),
                    child: const Text('Edit'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _delete(a),
                    style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: Color(0xFFFECACA))),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Delete'),
                  ),
                ],
                table: (items) => _accountsTable(items, statusById),
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
            if (_transfers.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Recent transfers', style: TextStyle(fontWeight: FontWeight.w500, color: TColors.slate700)),
                  const SizedBox(height: 8),
                  MobileCardList<Map>(
                    items: recent,
                    keyOf: (t) => tStr(t['poultryCashTransferId']),
                    primary: (t) => '${tStr(t['fromAccountName'])} → ${tStr(t['toAccountName'])}',
                    secondary: (t) => fmtDateTime(t['transferDate'], t, _offset),
                    trailing: (t) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: TBadge(tStr(t['status']), bg: Colors.white, fg: TColors.slate700, border: TColors.slate300),
                    ),
                    details: (t) => [
                      ('Date', fmtDateTime(t['transferDate'], t, _offset)),
                      ('From', tStr(t['fromAccountName'])),
                      ('To', tStr(t['toAccountName'])),
                      ('Amount', _fmt(tNum(t['amount']))),
                      ('Status', tStr(t['status'])),
                    ],
                    actions: (t) => [
                      if (tStr(t['status']) == 'Draft') ...[
                        OutlinedButton(
                          onPressed: () => _transferAction(t, 'approve'),
                          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF15803D), side: const BorderSide(color: Color(0xFFBBF7D0))),
                          child: const Text('Approve'),
                        ),
                        OutlinedButton(
                          onPressed: () => _transferAction(t, 'cancel'),
                          style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: Color(0xFFFECACA))),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ],
                    table: (items) => TrackerTable(
                      columns: const [
                        TCol('Date', width: 140),
                        TCol('From', width: 130),
                        TCol('To', width: 130),
                        TCol('Amount', right: true, width: 120),
                        TCol('Status', width: 100),
                        TCol('Actions', right: true, width: 170),
                      ],
                      rows: [
                        for (final t in items)
                          [
                            cellText(fmtDateTime(t['transferDate'], t, _offset)),
                            cellText(tStr(t['fromAccountName'])),
                            cellText(tStr(t['toAccountName'])),
                            Align(alignment: Alignment.centerRight, child: Text(_fmt(tNum(t['amount'])))),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TBadge(tStr(t['status']), bg: Colors.white, fg: TColors.slate700, border: TColors.slate300),
                            ),
                            Wrap(alignment: WrapAlignment.end, children: [
                              if (tStr(t['status']) == 'Draft') ...[
                                TextButton(onPressed: () => _transferAction(t, 'approve'), child: const Text('Approve')),
                                TextButton(onPressed: () => _transferAction(t, 'cancel'), child: const Text('Cancel')),
                              ],
                            ]),
                          ],
                      ],
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

const _clearingTones = {
  'Uncleared': (TColors.slate100, TColors.slate600),
  'Cleared': (TColors.emerald100, TColors.emerald700),
  'Disputed': (Color(0xFFFFE4E6), Color(0xFFBE123C)),
};

class CashAccountDetailScreen extends StatefulWidget {
  const CashAccountDetailScreen({super.key, required this.session, required this.company, required this.accountId, this.fromList = false});
  final Session session;
  final Company company;
  final int accountId;

  /// Opened from the Cash Account list, so Back (and Delete) return to it.
  final bool fromList;

  @override
  State<CashAccountDetailScreen> createState() => _CashAccountDetailScreenState();
}

class _CashAccountDetailScreenState extends State<CashAccountDetailScreen> {
  Map? _account;
  List<Map> _rows = [];
  bool _loading = true;
  final _search = TextEditingController();
  String _from = '', _to = '';
  int _page = 1, _pageSize = 10, _lastTotal = -1;
  FarmMoney _gh = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  int get _id => widget.accountId;

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
    // Settled separately: one failing does not hide the other.
    try {
      final a = await _api.get('/api/Poultry/cash-accounts/$_id', query: {'farmId': _farmId});
      if (mounted) setState(() => _account = a is Map ? a : null);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load account', description: e.message, error: true);
    }
    try {
      final t = await _api.get('/api/Poultry/cash-accounts/transactions', query: {'farmId': _farmId, 'cashAccountId': '$_id'});
      if (mounted) setState(() => _rows = rowsOf(t));
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load transactions', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setClearing(Map r, String status) async {
    try {
      await _api.post('/api/Poultry/cash-reconciliations/clearing', query: {'farmId': _farmId}, body: {
        'poultryCashAccountId': _id,
        'transactionIds': [tIntOrNull(r['poultryCashTransactionId'])],
        'clearingStatus': status,
        'userId': widget.session.tokens.userId,
      });
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not update clearing', description: e.message, error: true);
    }
  }

  Future<void> _recalculate() async {
    try {
      await _api.post('/api/Poultry/cash-accounts/reconcile-balances', query: {'farmId': _farmId});
      if (mounted) trackerToast(context, 'Balance recalculated from transactions');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Recalculate failed', description: e.message, error: true);
    }
  }

  Future<void> _delete() async {
    final name = tStr(_account?['accountName']);
    final ok = await confirmDelete(context,
        title: 'Remove ${name.isEmpty ? 'this account' : name}?',
        description: 'The account is deactivated so its transaction history stays intact.',
        confirmLabel: 'Remove account');
    if (!ok) return;
    try {
      await _api.delete('/api/Poultry/cash-accounts/$_id?farmId=${Uri.encodeQueryComponent(_farmId)}');
      if (!mounted) return;
      trackerToast(context, 'Cash account removed');
      _toList();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not remove account', description: e.message, error: true);
    }
  }

  /// The web's router.push("/poultry-cash-accounts").
  void _toList() => widget.fromList
      ? Navigator.of(context).pop()
      : Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => CashAccountsScreen(session: widget.session, company: widget.company)));

  Future<void> _adjust() async {
    if (_account == null) return;
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => AdjustBalanceDialog(session: widget.session, company: widget.company, account: _account!, fmt: _gh),
    );
    if (done == true) _load();
  }

  Widget _clearingCell(Map r) {
    final st = tStr(r['clearingStatus']).isEmpty ? 'Uncleared' : tStr(r['clearingStatus']);
    if (r['poultryCashReconciliationId'] != null) {
      final (bg, fg) = _clearingTones[st] ?? _clearingTones['Uncleared']!;
      return Tooltip(
        message: 'Cleared by cash count ${tStr(r['reconciliationReference'])}'.trim(),
        child: Align(alignment: Alignment.centerLeft, child: TBadge(st, bg: bg, fg: fg)),
      );
    }
    return AppSelect<String>(
      value: st,
      items: const [
        AppSelectItem(value: 'Uncleared', label: 'Uncleared'),
        AppSelectItem(value: 'Cleared', label: 'Cleared'),
        AppSelectItem(value: 'Disputed', label: 'Disputed'),
      ],
      onChanged: (v) {
        if (v != null && v != st) _setClearing(r, v);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final gh = _gh;
    final a = _account;
    final ledger = accountLedger(_rows, tNum(a?['openingBalance']));
    final totalIn = _rows.where((r) => tNum(r['amount']) > 0).fold<num>(0, (s, r) => s + tNum(r['amount']));
    final totalOut = _rows.where((r) => tNum(r['amount']) < 0).fold<num>(0, (s, r) => s + tNum(r['amount']).abs());
    final q = _search.text.trim().toLowerCase();
    final visible = ledger.where((r) {
      final day = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(tStr(r['transactionDate']))?[1];
      if (day != null) {
        if (_from.isNotEmpty && day.compareTo(_from) < 0) return false;
        if (_to.isNotEmpty && day.compareTo(_to) > 0) return false;
      }
      if (q.isNotEmpty && !['transactionType', 'description', 'sourceType'].any((k) => r[k] != null && '${r[k]}'.toLowerCase().contains(q))) {
        return false;
      }
      return true;
    }).toList();
    if (visible.length != _lastTotal) {
      _lastTotal = visible.length;
      _page = 1;
    }
    final pageRows = pageSlice(visible, _page, _pageSize);
    Widget stat(String label, num v, {Color? color}) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            Text(gh(v), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: color)),
          ]),
        );

    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-cash-accounts');
    return Scaffold(
      appBar: AppBar(
        leading: lead.leading,
        leadingWidth: lead.width,
        title: Text(tStr(a?['accountName']).isNotEmpty ? tStr(a?['accountName']) : 'Cash Account'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _toList,
                style: TextButton.styleFrom(foregroundColor: TColors.slate600, padding: EdgeInsets.zero),
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('Back to Cash Account'),
              ),
            ),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 24, color: _sky600),
              Text(a != null ? tStr(a['accountName']) : (_loading ? 'Loading…' : 'Account #$_id'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900)),
              if (a != null) TBadge(tStr(a['accountType']), bg: Colors.white, fg: TColors.slate700, border: TColors.slate300),
              if (a != null && a['isActive'] != true) const TBadge('Inactive', bg: TColors.amber100, fg: TColors.amber700),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: _recalculate, icon: const Icon(Icons.refresh, size: 16), label: const Text('Recalculate')),
              OutlinedButton.icon(
                onPressed: () => openAppHref(context, widget.session, widget.company, '/poultry-cash-reconciliation?accountId=$_id', label: 'Reconciliation'),
                icon: const Icon(Icons.balance, size: 16),
                label: const Text('Reconcile'),
              ),
              FilledButton.icon(onPressed: _adjust, icon: const Icon(Icons.balance, size: 16), label: const Text('Adjust balance')),
              OutlinedButton.icon(
                onPressed: _delete,
                style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: Color(0xFFFECACA))),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete'),
              ),
            ]),
            const SizedBox(height: 14),
            if (_loading)
              const Row(children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Loading…', style: TextStyle(color: TColors.slate500)),
              ])
            else if (a == null)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Account not found.', style: TextStyle(color: TColors.slate500))))
            else ...[
              twoUp([
                stat('Opening balance', tNum(a['openingBalance'])),
                stat('Total money in', totalIn, color: const Color(0xFF15803D)),
                stat('Total money out', totalOut, color: TColors.rose600),
                stat('Current balance', tNum(a['currentBalance'])),
              ]),
              const SizedBox(height: 14),
              ListFiltersCard(
                search: _search,
                searchPlaceholder: 'Search type, source or description',
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
              if (ledger.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No transactions yet for this account.', style: TextStyle(color: TColors.slate500))))
              else if (visible.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No transactions match your filters.', style: TextStyle(color: TColors.slate500))))
              else
                MobileCardList<Map>(
                  defaultOpen: false,
                  items: pageRows,
                  keyOf: (r) => tStr(r['poultryCashTransactionId']),
                  primary: (r) => '${tNum(r['amount']) < 0 ? '−' : '+'}${gh(tNum(r['amount']).abs())} · ${tStr(r['transactionType'])}',
                  secondary: (r) => '${fmtDateTime(r['transactionDate'], r, _offset)} · Bal ${gh(tNum(r['running']))}',
                  details: (r) => [
                    ('Date', fmtDateTime(r['transactionDate'], r, _offset)),
                    ('Type', tStr(r['transactionType'])),
                    ('Source', categoryLabel(r['sourceType'])),
                    ('Money in', tNum(r['amount']) > 0 ? gh(tNum(r['amount'])) : '—'),
                    ('Money out', tNum(r['amount']) < 0 ? gh(tNum(r['amount']).abs()) : '—'),
                    ('Running balance', gh(tNum(r['running']))),
                    ('Description', tStr(r['description']).isEmpty ? '—' : tStr(r['description'])),
                  ],
                  table: (items) => TrackerTable(
                    columns: const [
                      TCol('Date', width: 140),
                      TCol('Type', width: 130),
                      TCol('Source', width: 130),
                      TCol('Money in', right: true, width: 120),
                      TCol('Money out', right: true, width: 120),
                      TCol('Running balance', right: true, width: 140),
                      TCol('Cleared', width: 150),
                      TCol('Description', width: 220),
                    ],
                    rows: [
                      for (final r in items)
                        [
                          cellText(fmtDateTime(r['transactionDate'], r, _offset)),
                          cellText(tStr(r['transactionType'])),
                          cellText(categoryLabel(r['sourceType'])),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(tNum(r['amount']) > 0 ? gh(tNum(r['amount'])) : '—', style: const TextStyle(color: Color(0xFF15803D))),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(tNum(r['amount']) < 0 ? gh(tNum(r['amount']).abs()) : '—', style: const TextStyle(color: TColors.rose600)),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(gh(tNum(r['running'])), style: const TextStyle(fontWeight: FontWeight.w500)),
                          ),
                          _clearingCell(r),
                          Text(tStr(r['description']).isEmpty ? '—' : tStr(r['description'])),
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
          ],
        ),
      ),
    );
  }
}
