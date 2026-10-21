// Restaurant → Money → Owner Money, as `app/restaurant-owner-money/page.tsx`:
// contributions (the owner puts money in) and drawings (the owner takes money
// out). Both move cash on the ledger but are equity, so they never touch the
// Profit & Loss. API: /Restaurant/finance/owner-money (migration 323).

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
import 'restaurant_roles.dart' show restaurantRose;
import 'restaurant_widgets.dart';

class RestaurantOwnerMoneyScreen extends StatefulWidget {
  const RestaurantOwnerMoneyScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantOwnerMoneyScreen> createState() => _RestaurantOwnerMoneyScreenState();
}

class _RestaurantOwnerMoneyScreenState extends State<RestaurantOwnerMoneyScreen> {
  bool _loading = true;
  List<Map> _entries = [];
  List<Map> _accounts = [];
  String _from = '${DateTime.now().year}-01-01';
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
    try {
      final r = await Future.wait([
        _api.get(rFin('/owner-money', _farmId, {'from': _from, 'to': _to})),
        loadRestaurantAccounts(_api, _farmId),
      ]);
      if (!mounted) return;
      setState(() {
        _entries = rowsOf(r[0]);
        _accounts = [for (final a in r[1] as List<Map>) if (a['isActive'] == true) a];
        _page = 1;
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load owner money', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _record(String entryType) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _RecordDialog(api: _api, farmId: _farmId, entryType: entryType, accounts: _accounts, gh: _gh),
    );
    if (done == true) _load();
  }

  Future<void> _reverse(Map e) async {
    final draw = e['entryType'] == 'Draw';
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => RReasonDialog(
        title: 'Reverse ${draw ? 'drawing' : 'contribution'}',
        description:
            '${_number(e)} — ${_gh(tNum(e['amount']))} ${draw ? 'goes back into' : 'comes back out of'} ${tStr(e['accountName'])}.',
        options: reversalReasons,
        keepLabel: 'Keep it',
        confirmLabel: 'Reverse',
        busyLabel: 'Reversing...',
        errorTitle: 'Could not reverse',
        submit: (reason) => _api.post(rFin('/owner-money/${tIntOrNull(e['ownerMoneyId'])}/reverse', _farmId), body: {'reason': reason}),
      ),
    );
    if (done == true) {
      if (mounted) trackerToast(context, 'Reversed', description: 'The entry was reversed and the cash put back.');
      _load();
    }
  }

  String _number(Map e) => tStr(e['entryNumber']).isNotEmpty ? tStr(e['entryNumber']) : '#${tIntOrNull(e['ownerMoneyId'])}';

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-owner-money');
    Widget body;
    if (_loading) {
      body = const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: LoadingLine('Loading…')));
    } else if (!_canView) {
      body = const TCard(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Text('You do not have access to Owner Money.', style: TextStyle(color: TColors.slate600))),
        ),
      );
    } else {
      final posted = [for (final e in _entries) if (e['status'] == 'Posted') e];
      num sum(String t) => posted.where((e) => e['entryType'] == t).fold<num>(0, (s, e) => s + tNum(e['amount']));
      final putIn = sum('Contribution'), takenOut = sum('Draw'), net = putIn - takenOut;
      final nIn = posted.where((e) => e['entryType'] == 'Contribution').length;
      final nOut = posted.where((e) => e['entryType'] == 'Draw').length;
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RPageHeader(
          icon: Icons.volunteer_activism_outlined,
          title: 'Owner Money',
          subtitle: 'Money the owner puts into or takes out of the business',
          actions: [
            roseButton('Record contribution', () => _record('Contribution'), icon: Icons.download),
            OutlinedButton.icon(onPressed: () => _record('Draw'), icon: const Icon(Icons.upload, size: 16), label: const Text('Record draw')),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Contributions and drawings move cash but are not income or expenses, so they never change profit.',
            style: TextStyle(fontSize: 13, color: TColors.slate500)),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.end, children: [
          SizedBox(width: 160, child: rField('From', rDateInput(_from, (v) => setState(() => _from = v), max: _to))),
          SizedBox(width: 160, child: rField('To', rDateInput(_to, (v) => setState(() => _to = v), min: _from))),
          OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.calendar_today_outlined, size: 16), label: const Text('Load')),
        ]),
        const SizedBox(height: 12),
        twoColumns([
          MoneyStat(label: 'Contributions in range', value: _gh(putIn), hint: '$nIn record(s)', accent: 'emerald'),
          MoneyStat(label: 'Draws in range', value: _gh(takenOut), hint: '$nOut record(s)', accent: 'orange'),
          MoneyStat(label: 'Net owner funding', value: _gh(net), hint: 'Contributions less draws', accent: net >= 0 ? 'emerald' : 'rose'),
        ]),
        const SizedBox(height: 16),
        if (_entries.isEmpty)
          TCard(
            child: REmptyState(
              icon: Icons.volunteer_activism_outlined,
              title: 'No owner money in this period',
              description: 'Record money the owner puts in or takes out',
              actionLabel: 'Record contribution',
              onAction: () => _record('Contribution'),
            ),
          )
        else
          TCard(
            padding: const EdgeInsets.all(10),
            child: MobileCardList<Map>(
              items: pageSlice(_entries, _page, _pageSize),
              striped: true,
              keyOf: (e) => '${e['ownerMoneyId']}',
              primary: (e) => '${_number(e)} · ${e['entryType'] == 'Contribution' ? 'Contribution' : 'Draw'}',
              secondary: (e) => '${rDateOnly(e['entryDate'])}${tStr(e['ownerName']).isNotEmpty ? ' · ${e['ownerName']}' : ''}',
              trailing: (e) => rStatusBadge(tStr(e['status']), fg: e['status'] != 'Posted' ? TColors.slate500 : TColors.slate700),
              highlights: (e) => [
                Highlight('Amount', _gh(tNum(e['amount'])),
                    accent: e['entryType'] == 'Contribution' ? Accent.emerald : Accent.amber, wide: true, strike: e['status'] != 'Posted'),
              ],
              details: (e) => [
                ('Account', tStr(e['accountName']).isEmpty ? '—' : tStr(e['accountName'])),
                ('Owner', tStr(e['ownerName']).isEmpty ? '—' : tStr(e['ownerName'])),
                if (tStr(e['reversalReason']).isNotEmpty) ('Reversal reason', tStr(e['reversalReason'])),
              ],
              actions: (e) => e['status'] == 'Posted'
                  ? [
                      OutlinedButton.icon(
                          onPressed: () => _reverse(e), icon: const Icon(Icons.undo, size: 16), label: const Text('Reverse')),
                    ]
                  : [],
              table: _table,
              pager: CompactPager(
                total: _entries.length,
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
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Owner Money')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [body]),
      ),
    );
  }

  Widget _table(List<Map> rows) => TrackerTable(
        columns: const [
          TCol('Number', width: 110),
          TCol('Date', width: 100),
          TCol('Type', width: 120),
          TCol('Account', width: 130),
          TCol('Owner', width: 120),
          TCol('Amount', right: true, width: 110),
          TCol('Status', width: 160),
          TCol('Actions', right: true, width: 110),
        ],
        rows: [
          for (final e in rows)
            () {
              final reversed = e['status'] != 'Posted';
              final contribution = e['entryType'] == 'Contribution';
              final grey = reversed ? TColors.slate400 : null;
              return [
                cellText(_number(e), color: grey),
                cellText(rDateOnly(e['entryDate']), color: grey),
                Align(
                  alignment: Alignment.centerLeft,
                  child: contribution
                      ? rStatusBadge('Contribution', bg: const Color(0xFFF0FDF4), fg: const Color(0xFF15803D), border: const Color(0xFFBBF7D0))
                      : rStatusBadge('Draw', bg: TColors.amber50, fg: TColors.amber700, border: TColors.amber200),
                ),
                cellText(tStr(e['accountName']), color: grey),
                cellText(tStr(e['ownerName']).isEmpty ? '—' : tStr(e['ownerName']), color: grey),
                Text(_gh(tNum(e['amount'])),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: reversed ? TColors.slate400 : (contribution ? const Color(0xFF15803D) : TColors.amber700),
                      decoration: reversed ? TextDecoration.lineThrough : null,
                    )),
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  rStatusBadge(tStr(e['status']), fg: reversed ? TColors.slate500 : TColors.slate700),
                  if (reversed && tStr(e['reversalReason']).isNotEmpty)
                    Text(tStr(e['reversalReason']), style: const TextStyle(fontSize: 11, color: TColors.slate400)),
                ]),
                reversed
                    ? const SizedBox()
                    : OutlinedButton.icon(onPressed: () => _reverse(e), icon: const Icon(Icons.undo, size: 16), label: const Text('Reverse')),
              ];
            }(),
        ],
      );
}

class _RecordDialog extends StatefulWidget {
  const _RecordDialog({required this.api, required this.farmId, required this.entryType, required this.accounts, required this.gh});
  final ApiClient api;
  final String farmId;
  final String entryType;
  final List<Map> accounts;
  final FarmMoney gh;

  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> {
  late String? _account = widget.accounts.length == 1 ? '${tIntOrNull(widget.accounts.first['cashAccountId'])}' : null;
  final _amount = TextEditingController();
  final _owner = TextEditingController();
  final _notes = TextEditingController();
  String _date = rTodayIso();
  bool _saving = false;

  bool get _contribution => widget.entryType == 'Contribution';

  @override
  void dispose() {
    for (final c in [_amount, _owner, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final amount = num.tryParse(_amount.text.trim());
    if (_account == null) {
      trackerToast(context, 'Pick an account', description: 'Choose which account the money goes into or comes out of.', error: true);
      return;
    }
    if (amount == null || amount <= 0) {
      trackerToast(context, 'Enter an amount', description: 'The amount must be more than zero.', error: true);
      return;
    }
    if (_date.isNotEmpty && _date.compareTo(rTodayIso()) > 0) {
      trackerToast(context, 'Date is in the future', description: 'Pick today or an earlier date.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.api.post(rFin('/owner-money', widget.farmId), body: {
        'entryType': widget.entryType,
        'cashAccountId': int.parse(_account!),
        'amount': amount,
        if (_date.isNotEmpty) 'entryDate': _date,
        'ownerName': _owner.text.trim().isEmpty ? null : _owner.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (!mounted) return;
      trackerToast(context, 'Saved', description: _contribution ? 'Contribution recorded.' : 'Drawing recorded.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not save', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: rDialog(
          title: _contribution ? 'Record contribution' : 'Record drawing',
          description: _contribution
              ? 'Money the owner puts into the business. It is not income.'
              : 'Money the owner takes out of the business. It is not an expense.',
          children: [
            rField(
              _contribution ? 'Money goes into' : 'Money comes out of',
              AppSelect<String>(
                value: _account,
                hintText: 'Select account',
                items: rAccountItems(widget.accounts, widget.gh.call),
                onChanged: (v) => setState(() => _account = v),
              ),
              required: true,
            ),
            rField('Amount', rNumberInput(_amount), required: true),
            rField('Date', rDateInput(_date, (v) => setState(() => _date = v), max: rTodayIso())),
            rField('Owner name', AppInput(controller: _owner, hintText: 'Optional')),
            rField('Notes', AppInput(controller: _notes, hintText: 'Optional')),
          ],
          actions: [
            rCancel(context, 'Cancel', busy: _saving),
            rConfirm(_saving ? 'Saving...' : (_contribution ? 'Record contribution' : 'Record drawing'), _saving ? null : _save,
                color: restaurantRose),
          ],
        ),
      );
}
