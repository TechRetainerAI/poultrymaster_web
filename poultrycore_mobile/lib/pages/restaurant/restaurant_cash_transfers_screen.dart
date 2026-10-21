// Restaurant → Money → Cash Transfers, as `app/restaurant-cash-transfers/page.tsx`:
// move money between cash accounts (e.g. cash box to bank deposit). Both sides
// post in one call; a reversal posts the opposite pair dated today.
// API: /Restaurant/finance/transfers (migration 323).

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart';
import '../poultry/reports/report_format.dart' show FarmMoney;
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart' show CompactPager, LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/reason_select.dart' show reversalReasons;
import 'restaurant_money_kit.dart';
import 'restaurant_widgets.dart';

/// mostUsed: the value that appears most often, or null.
String? mostUsed(Iterable<Object?> values) {
  final counts = <String, int>{};
  for (final v in values) {
    final s = tStr(v);
    if (s.isNotEmpty) counts[s] = (counts[s] ?? 0) + 1;
  }
  String? best;
  for (final e in counts.entries) {
    if (best == null || e.value > counts[best]!) best = e.key;
  }
  return best;
}

/// The page's five cards. "Today" and "this month" are UTC, as the web's
/// `new Date().toISOString()`.
({num today, num month, int count, num moved, int reversed, String? topFrom, String? topTo}) transferStats(List<Map> transfers,
    {DateTime? now}) {
  final posted = [for (final t in transfers) if (t['status'] == 'Posted') t];
  final iso = (now ?? DateTime.now()).toUtc().toIso8601String();
  num sumWhere(bool Function(String) f) =>
      posted.where((t) => f(tStr(t['transferDate']))).fold<num>(0, (s, t) => s + tNum(t['amount']));
  return (
    today: sumWhere((d) => d.length >= 10 && d.substring(0, 10) == iso.substring(0, 10)),
    month: sumWhere((d) => d.length >= 7 && d.substring(0, 7) == iso.substring(0, 7)),
    count: posted.length,
    moved: posted.fold<num>(0, (s, t) => s + tNum(t['amount'])),
    reversed: transfers.where((t) => t['status'] == 'Reversed').length,
    topFrom: mostUsed(posted.map((t) => t['fromAccountName'])),
    topTo: mostUsed(posted.map((t) => t['toAccountName'])),
  );
}

String _day(Object? d) => tStr(d).length >= 10 ? tStr(d).substring(0, 10) : tStr(d);
String _number(Map t) => tStr(t['transferNumber']).isNotEmpty ? tStr(t['transferNumber']) : '#${tIntOrNull(t['transferId'])}';

Widget _transferStatus(Object? s) => tStr(s) == 'Posted'
    ? rStatusBadge('Posted', bg: const Color(0xFFDCFCE7), fg: const Color(0xFF166534), border: const Color(0xFFBBF7D0))
    : rStatusBadge(tStr(s), bg: TColors.slate100, fg: TColors.slate600);

class RestaurantCashTransfersScreen extends StatefulWidget {
  const RestaurantCashTransfersScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantCashTransfersScreen> createState() => _RestaurantCashTransfersScreenState();
}

class _RestaurantCashTransfersScreenState extends State<RestaurantCashTransfersScreen> {
  bool _loading = true;
  List<Map> _accounts = [];
  List<Map> _transfers = [];
  String _from = '${rTodayIso().substring(0, 8)}01';
  String _to = rTodayIso();
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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([loadRestaurantAccounts(_api, _farmId), _api.get(rFin('/transfers', _farmId, {'from': _from, 'to': _to}))]);
      if (!mounted) return;
      setState(() {
        _accounts = r[0] as List<Map>;
        _transfers = rowsOf(r[1]);
        _page = 1;
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Error loading transfers', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _new() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _TransferDialog(
          api: _api, farmId: _farmId, accounts: [for (final a in _accounts) if (a['isActive'] == true) a], gh: _gh),
    );
    if (done == true) _load();
  }

  Future<void> _reverse(Map t) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => RReasonDialog(
        title: 'Reverse transfer',
        description:
            '${_number(t)}: ${_gh(tNum(t['amount']))} from ${tStr(t['fromAccountName'])} to ${tStr(t['toAccountName'])}. The opposite pair will be posted dated today.',
        options: reversalReasons,
        keepLabel: 'Cancel',
        confirmLabel: 'Reverse',
        busyLabel: 'Reversing...',
        errorTitle: 'Could not reverse transfer',
        destructive: false,
        submit: (reason) => _api.post(rFin('/transfers/${tIntOrNull(t['transferId'])}/reverse', _farmId), body: {'reason': reason}),
      ),
    );
    if (done == true) {
      if (mounted) trackerToast(context, 'Transfer reversed');
      _load();
    }
  }

  Widget _route(Map t, {TextStyle? style}) => Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
        Text(tStr(t['fromAccountName']), style: style),
        const Icon(Icons.arrow_forward, size: 12, color: TColors.slate400),
        Text(tStr(t['toAccountName']), style: style),
      ]);

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-cash-transfers');
    Widget body;
    if (!_canView) {
      body = const TCard(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Text('You do not have access to Cash Transfers.', style: TextStyle(color: TColors.slate600))),
        ),
      );
    } else if (_loading) {
      body = const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: LoadingLine('Loading…')));
    } else {
      final s = transferStats(_transfers);
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RPageHeader(
          icon: Icons.swap_horiz,
          title: 'Cash Transfers',
          subtitle: 'Move money between your cash accounts',
          actions: [roseButton('Record transfer', _new)],
        ),
        const SizedBox(height: 8),
        const Text('A transfer posts both sides at once. Reversing it posts the opposite pair dated today — the original stays on record.',
            style: TextStyle(fontSize: 13, color: TColors.slate500)),
        const SizedBox(height: 14),
        twoColumns([
          MoneyStat(label: 'Moved today', value: _gh(s.today), accent: 'rose'),
          MoneyStat(label: 'Moved this month', value: _gh(s.month), accent: 'indigo'),
          MoneyStat(
            label: 'Transfers on record',
            value: '${s.count}',
            hint: s.reversed > 0 ? '${s.reversed} reversed · ${_gh(s.moved)} moved' : '${_gh(s.moved)} moved',
          ),
          MoneyStat(label: 'Most used source', value: s.topFrom ?? '—'),
          MoneyStat(label: 'Most used destination', value: s.topTo ?? '—'),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.end, children: [
          SizedBox(width: 160, child: rField('From', rDateInput(_from, (v) => setState(() => _from = v)))),
          SizedBox(width: 160, child: rField('To', rDateInput(_to, (v) => setState(() => _to = v)))),
          OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.calendar_today_outlined, size: 16), label: const Text('Filter')),
        ]),
        const SizedBox(height: 14),
        if (_transfers.isEmpty)
          TCard(
            child: REmptyState(
              icon: Icons.swap_horiz,
              title: 'No transfers in this period',
              description: 'Move money between accounts, e.g. a bank deposit from the cash box.',
              actionLabel: 'Record transfer',
              onAction: _new,
            ),
          )
        else
          TCard(
            padding: const EdgeInsets.all(10),
            child: MobileCardList<Map>(
              items: pageSlice(_transfers, _page, _pageSize),
              striped: true,
              keyOf: (t) => '${t['transferId']}',
              primary: (t) => '${tStr(t['fromAccountName'])} → ${tStr(t['toAccountName'])}',
              secondary: (t) => '${_number(t)} · ${_day(t['transferDate'])}',
              trailing: (t) => _transferStatus(t['status']),
              highlights: (t) => [
                Highlight('Amount', _gh(tNum(t['amount'])), accent: Accent.rose, wide: true, strike: t['status'] != 'Posted'),
              ],
              details: (t) => [
                ('Source', tStr(t['fromAccountName']).isEmpty ? '—' : tStr(t['fromAccountName'])),
                ('Destination', tStr(t['toAccountName']).isEmpty ? '—' : tStr(t['toAccountName'])),
                ('Reference', tStr(t['reference']).isEmpty ? '—' : tStr(t['reference'])),
                ('Created by', tStr(t['createdBy']).isEmpty ? '—' : tStr(t['createdBy'])),
                if (tStr(t['notes']).isNotEmpty) ('Notes', tStr(t['notes'])),
                if (t['status'] != 'Posted' && tStr(t['reversalReason']).isNotEmpty) ('Reversed', tStr(t['reversalReason'])),
              ],
              actions: (t) => t['status'] == 'Posted'
                  ? [OutlinedButton.icon(onPressed: () => _reverse(t), icon: const Icon(Icons.undo, size: 16), label: const Text('Reverse'))]
                  : [],
              table: (rows) => TrackerTable(
                columns: const [
                  TCol('Number', width: 110),
                  TCol('Date', width: 100),
                  TCol('From → To', width: 220),
                  TCol('Amount', right: true, width: 110),
                  TCol('Reference', width: 130),
                  TCol('Status', width: 150),
                  TCol('Created by', width: 130),
                  TCol('Actions', right: true, width: 110),
                ],
                rows: [
                  for (final t in rows)
                    [
                      cellText(_number(t), bold: true),
                      cellText(_day(t['transferDate']), color: TColors.slate500),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        _route(t),
                        if (tStr(t['notes']).isNotEmpty) Text(tStr(t['notes']), style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                      ]),
                      cellText(_gh(tNum(t['amount'])), bold: true),
                      cellText(tStr(t['reference']).isEmpty ? '—' : tStr(t['reference'])),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        _transferStatus(t['status']),
                        if (t['status'] != 'Posted' && tStr(t['reversalReason']).isNotEmpty)
                          Text(tStr(t['reversalReason']), style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                      ]),
                      cellText(tStr(t['createdBy']).isEmpty ? '—' : tStr(t['createdBy'])),
                      t['status'] == 'Posted'
                          ? OutlinedButton.icon(onPressed: () => _reverse(t), icon: const Icon(Icons.undo, size: 16), label: const Text('Reverse'))
                          : const SizedBox(),
                    ],
                ],
              ),
              pager: CompactPager(
                total: _transfers.length,
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
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Cash Transfers')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [body]),
      ),
    );
  }
}

class _TransferDialog extends StatefulWidget {
  const _TransferDialog({required this.api, required this.farmId, required this.accounts, required this.gh});
  final ApiClient api;
  final String farmId;
  final List<Map> accounts;
  final FarmMoney gh;

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  String? _fromId, _toId;
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  String _date = rTodayIso();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_amount, _reference, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String t, String d) => trackerToast(context, t, description: d, error: true);

  Future<void> _post() async {
    final amount = num.tryParse(_amount.text.trim());
    if (_fromId == null || _toId == null) return _toast('Pick both accounts', 'Choose where the money comes from and where it goes.');
    if (_fromId == _toId) return _toast('Same account', 'The from and to accounts must be different.');
    if (amount == null || amount <= 0) return _toast('Invalid amount', 'Enter an amount greater than zero.');
    if (_date.isNotEmpty && _date.compareTo(rTodayIso()) > 0) return _toast('Future date', 'A transfer cannot be dated in the future.');
    setState(() => _saving = true);
    try {
      await widget.api.post(rFin('/transfers', widget.farmId), body: {
        'fromAccountId': int.parse(_fromId!),
        'toAccountId': int.parse(_toId!),
        'amount': amount,
        if (_date.isNotEmpty) 'transferDate': _date,
        'reference': _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (!mounted) return;
      trackerToast(context, 'Transfer posted', description: '${widget.gh(amount)} moved.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not post transfer', e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final toOptions = [for (final a in widget.accounts) if ('${tIntOrNull(a['cashAccountId'])}' != _fromId) a];
    return PopScope(
      canPop: !_saving,
      child: rDialog(
        title: 'New transfer',
        description: 'Move money from one account to another.',
        children: [
          rField(
            'From account',
            AppSelect<String>(
              value: _fromId,
              hintText: 'Select account',
              items: rAccountItems(widget.accounts, widget.gh.call),
              onChanged: (v) => setState(() {
                _fromId = v;
                if (_toId == v) _toId = null;
              }),
            ),
            required: true,
          ),
          rField(
            'To account',
            AppSelect<String>(
              key: ValueKey('to-$_fromId'),
              value: _toId,
              hintText: 'Select account',
              items: rAccountItems(toOptions, widget.gh.call),
              onChanged: (v) => setState(() => _toId = v),
            ),
            required: true,
          ),
          rField('Amount', rNumberInput(_amount), required: true),
          rField('Date', rDateInput(_date, (v) => setState(() => _date = v), max: rTodayIso())),
          rField('Reference', AppInput(controller: _reference, hintText: 'e.g. Deposit slip number')),
          rField('Notes', AppInput(controller: _notes, hintText: 'Optional')),
        ],
        actions: [
          rCancel(context, 'Cancel', busy: _saving),
          rConfirm(_saving ? 'Posting...' : 'Post transfer', _saving ? null : _post),
        ],
      ),
    );
  }
}
