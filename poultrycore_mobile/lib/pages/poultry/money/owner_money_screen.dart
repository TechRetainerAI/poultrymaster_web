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
import '../sales/balances_logic.dart' show entryTimestamp, pageSlice;
import '../sales/balances_widgets.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';
import 'money_widgets.dart';

/// Poultry → Money → Owner Money, as `app/poultry-owner-money/page.tsx`: what
/// the owner put in and took out. A contribution is not revenue and a draw is
/// not an expense — both move cash, neither touches profit.

const ownerPaymentMethods = ['Cash', 'BankTransfer', 'MoMo', 'Cheque', 'Card', 'Other'];
const ownerTypeFilters = ['All', 'Contribution', 'Draw'];
const ownerStatusFilters = ['All', 'Posted', 'Reversed'];

const _orange100 = Color(0xFFFFEDD5);
const _orange600 = Color(0xFFEA580C);
const _orange700 = Color(0xFFC2410C);
const _orange800 = Color(0xFF9A3412);

/// The page's filters: type and status, then filterByDateAndSearch on
/// transactionDate (calendar days, inclusive) and the five search keys.
List<Map> filterOwnerMoney(List<Map> rows,
    {String type = 'All', String status = 'All', String search = '', String from = '', String to = ''}) {
  final s = search.trim().toLowerCase();
  return rows.where((r) {
    if (type != 'All' && tStr(r['transactionType']) != type) return false;
    if (status != 'All' && tStr(r['status']) != status) return false;
    if (from.isNotEmpty || to.isNotEmpty) {
      final day = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(tStr(r['transactionDate']))?[1];
      if (day != null) {
        if (from.isNotEmpty && day.compareTo(from) < 0) return false;
        if (to.isNotEmpty && day.compareTo(to) > 0) return false;
      }
    }
    if (s.isNotEmpty) {
      final hit = ['transactionNumber', 'ownerName', 'accountName', 'referenceNumber', 'notes']
          .any((k) => r[k] != null && '${r[k]}'.toLowerCase().contains(s));
      if (!hit) return false;
    }
    return true;
  }).toList();
}

String ownerNumber(Map r) => tStr(r['transactionNumber']).isNotEmpty ? tStr(r['transactionNumber']) : '#${tStr(r['sourceId'])}';
String _dash(Object? v) => tStr(v).isEmpty ? '–' : tStr(v);

class OwnerMoneyScreen extends StatefulWidget {
  const OwnerMoneyScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<OwnerMoneyScreen> createState() => _OwnerMoneyScreenState();
}

class _OwnerMoneyScreenState extends State<OwnerMoneyScreen> {
  List<Map> _accounts = [];
  List<Map> _rows = [];
  Map? _summary;
  bool _loading = true;

  String _type = 'All', _status = 'All';
  final _search = TextEditingController();
  String _from = '', _to = '';
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
      final r = await Future.wait([
        _api.get('/api/Poultry/cash-accounts', query: q),
        _api.get('/api/Poultry/owner-money', query: q),
        _api.get('/api/Poultry/owner-money/summary', query: q),
      ]);
      if (!mounted) return;
      setState(() {
        _accounts = rowsOf(r[0]);
        _rows = rowsOf(r[1]);
        _summary = r[2] is Map ? r[2] as Map : null;
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load owner money', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  String _when(Map r) => fmtDateTime(r['transactionDate'], r, _offset);

  Future<void> _record(String type) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => OwnerMoneyDialog(
        session: widget.session,
        company: widget.company,
        type: type,
        accounts: _accounts,
        fmt: _fmt,
      ),
    );
    if (done == true) _load();
  }

  Future<void> _reverse(Map r) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => ReverseOwnerMoneyDialog(
        session: widget.session,
        company: widget.company,
        row: r,
        fmt: _fmt,
        when: _when(r),
      ),
    );
    if (done == true) _load();
  }

  (Color, Color) _typeTone(String t) => t == 'Contribution' ? (TColors.emerald100, TColors.emerald800) : (_orange100, _orange800);

  Widget _reverseButton(Map r) => OutlinedButton.icon(
        onPressed: () => _reverse(r),
        icon: const Icon(Icons.undo, size: 16),
        label: const Text('Reverse'),
      );

  Widget _table(List<Map> items) {
    Widget badge(String text, Color bg, Color fg) => Align(alignment: Alignment.centerLeft, child: TBadge(text, bg: bg, fg: fg));
    return TrackerTable(
      columns: const [
        TCol('Date', width: 140),
        TCol('Number', width: 130),
        TCol('Owner'),
        TCol('Type', width: 120),
        TCol('Amount', right: true, width: 130),
        TCol('Cash account', width: 130),
        TCol('Method'),
        TCol('Reference'),
        TCol('Status', width: 100),
        TCol('', width: 120),
      ],
      rows: [
        for (final o in items)
          [
            cellText(_when(o)),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(ownerNumber(o), style: const TextStyle(fontWeight: FontWeight.w500)),
              if (tStr(o['source']) == 'CashAdjustment')
                const Text('From the Cash page', style: TextStyle(fontSize: 11, color: TColors.slate500)),
            ]),
            cellText(_dash(o['ownerName'])),
            Builder(builder: (_) {
              final (bg, fg) = _typeTone(tStr(o['transactionType']));
              return badge(tStr(o['transactionType']), bg, fg);
            }),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${tStr(o['transactionType']) == 'Draw' ? '−' : '+'}${_fmt(tNum(o['amount']))}',
                style: tStr(o['status']) == 'Reversed'
                    ? const TextStyle(decoration: TextDecoration.lineThrough, color: TColors.slate400)
                    : const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            cellText(_dash(o['accountName'])),
            Text(_dash(o['paymentMethod']), style: const TextStyle(color: TColors.slate500)),
            Text(_dash(o['referenceNumber']), style: const TextStyle(color: TColors.slate500)),
            tStr(o['status']) == 'Reversed'
                ? badge(tStr(o['status']), TColors.slate100, TColors.slate700)
                : badge(tStr(o['status']), TColors.sky100, TColors.sky800),
            Align(
              alignment: Alignment.centerRight,
              child: tStr(o['status']) == 'Posted' && tStr(o['source']) == 'OwnerMoney'
                  ? _reverseButton(o)
                  : tStr(o['source']) == 'CashAdjustment'
                      ? const Text('Cash page', style: TextStyle(fontSize: 11, color: TColors.slate500))
                      : const SizedBox.shrink(),
            ),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-owner-money');
    final visible = filterOwnerMoney(_rows, type: _type, status: _status, search: _search.text, from: _from, to: _to);
    if (visible.length != _lastTotal) {
      _lastTotal = visible.length;
      _page = 1;
    }
    final pageRows = pageSlice(visible, _page, _pageSize);
    final s = _summary;
    final net = tNum(s?['netFunding']);

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Owner Money')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.account_balance_wallet_outlined, size: 24, color: TColors.emerald600),
              SizedBox(width: 8),
              Expanded(
                child: Text('Owner Money', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900)),
              ),
            ]),
            const SizedBox(height: 4),
            Text.rich(
              const TextSpan(children: [
                TextSpan(text: 'Money the owner puts into the business and takes out of it. A contribution is'),
                TextSpan(text: ' not revenue', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' and a draw is '),
                TextSpan(text: 'not an expense', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' — both move cash, neither touches profit.'),
              ]),
              style: const TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: () => _record('Contribution'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.arrow_circle_down_outlined, size: 18),
                label: const Text('Record contribution'),
              ),
              OutlinedButton.icon(
                onPressed: () => _record('Draw'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.arrow_circle_up_outlined, size: 18),
                label: const Text('Record draw'),
              ),
            ]),
            const SizedBox(height: 14),
            twoUp([
              moneyStat('Total contributions', _fmt(tNum(s?['totalContributions'])),
                  hint: '${tIntOrNull(s?['contributionCount']) ?? 0} record(s)', color: TColors.emerald700),
              moneyStat('Total draws', _fmt(tNum(s?['totalDraws'])), hint: '${tIntOrNull(s?['drawCount']) ?? 0} record(s)', color: _orange700),
              moneyStat('Net owner funding', _fmt(net), hint: 'Contributions less draws', color: net >= 0 ? TColors.emerald700 : TColors.rose600),
              moneyStat('Contributions in range', _fmt(tNum(s?['periodContributions']))),
              moneyStat('Draws in range', _fmt(tNum(s?['periodDraws']))),
            ]),
            const SizedBox(height: 14),
            ListFiltersCard(
              search: _search,
              searchPlaceholder: 'Search number, owner, account, reference or note',
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
              extras: [
                Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  for (final t in ownerTypeFilters) filterChipButton(t, _type == t, () => setState(() => _type = t)),
                  Container(width: 1, height: 28, color: TColors.slate200),
                  for (final st in ownerStatusFilters) filterChipButton(st, _status == st, () => setState(() => _status = st), secondary: true),
                ]),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Row(children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Loading…', style: TextStyle(color: TColors.slate500)),
              ])
            else if (visible.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  _rows.isEmpty
                      ? 'Nothing recorded yet. Use the buttons above when the owner puts money in or takes it out.'
                      : 'Nothing matches these filters.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: TColors.slate500),
                ),
              )
            else
              MobileCardList<Map>(
                striped: true,
                items: pageRows,
                // Keyed on source + id: a Cash-page row carries poultryOwnerMoneyId 0.
                keyOf: (o) => '${tStr(o['source'])}:${tStr(o['sourceId'])}',
                primary: ownerNumber,
                secondary: (o) => '${_when(o)} · ${_dash(o['accountName'])}',
                trailing: (o) {
                  final reversed = tStr(o['status']) == 'Reversed';
                  final (bg, fg) = reversed ? (TColors.slate100, TColors.slate700) : _typeTone(tStr(o['transactionType']));
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: TBadge(reversed ? 'Reversed' : tStr(o['transactionType']), bg: bg, fg: fg),
                  );
                },
                highlights: (o) => [
                  Highlight(tStr(o['transactionType']) == 'Contribution' ? 'In' : 'Out', _fmt(tNum(o['amount']))),
                ],
                details: (o) => [
                  ('Type', tStr(o['transactionType'])),
                  ('Owner', _dash(o['ownerName'])),
                  ('Account', _dash(o['accountName'])),
                  ('Method', _dash(o['paymentMethod'])),
                  ('Reference', _dash(o['referenceNumber'])),
                  ('Notes', _dash(o['notes'])),
                  if (tStr(o['status']) == 'Reversed') ('Reversed', _dash(o['reversalReason'])),
                ],
                actions: (o) => [
                  // Recorded on the Cash page, so it is edited and deleted there.
                  if (tStr(o['status']) == 'Posted' && tStr(o['source']) == 'OwnerMoney') _reverseButton(o),
                  if (tStr(o['source']) == 'CashAdjustment')
                    const Text('Recorded on the Cash page — edit it there.', style: TextStyle(fontSize: 11, color: TColors.slate500)),
                ],
                table: _table,
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
        ),
      ),
    );
  }
}

/// One dialog for both directions — they differ by a single field.
class OwnerMoneyDialog extends StatefulWidget {
  const OwnerMoneyDialog({
    super.key,
    required this.session,
    required this.company,
    required this.type,
    required this.accounts,
    required this.fmt,
  });
  final Session session;
  final Company company;

  /// "Contribution" or "Draw".
  final String type;
  final List<Map> accounts;
  final FarmMoney fmt;

  @override
  State<OwnerMoneyDialog> createState() => _OwnerMoneyDialogState();
}

class _OwnerMoneyDialogState extends State<OwnerMoneyDialog> {
  final _amount = TextEditingController(text: '0');
  final _owner = TextEditingController();
  final _ref = TextEditingController();
  final _notes = TextEditingController();
  String _account = '';
  String _method = 'Cash';
  late String _date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  bool _saving = false;

  bool get _isDraw => widget.type == 'Draw';
  num get _amountNum => num.tryParse(_amount.text) ?? 0;
  Map? get _acc => widget.accounts.where((a) => tStr(a['poultryCashAccountId']) == _account).firstOrNull;
  num get _balance => tNum(_acc?['currentBalance']);
  bool get _allowsNegative => _acc?['allowNegativeBalance'] == true;
  num get _after => _isDraw ? _balance - _amountNum : _balance + _amountNum;
  bool get _wouldOverdraw => _isDraw && _account.isNotEmpty && _amountNum > 0 && _after < 0 && !_allowsNegative;

  @override
  void dispose() {
    for (final c in [_amount, _owner, _ref, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_account.isEmpty) {
      trackerToast(context, 'Pick a cash account', error: true);
      return;
    }
    if (_amountNum <= 0) {
      trackerToast(context, 'Enter an amount', error: true);
      return;
    }
    setState(() => _saving = true);
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    try {
      await widget.session.farmClient.post('/api/Poultry/owner-money', body: {
        'transactionType': widget.type,
        'amount': _amountNum,
        'poultryCashAccountId': int.parse(_account),
        // Today gets a real clock time so it sorts to the top; a back-dated entry keeps midnight.
        'transactionDate': entryTimestamp(_date),
        'paymentMethod': _method.isEmpty ? null : _method,
        'ownerName': opt(_owner),
        'referenceNumber': opt(_ref),
        'notes': opt(_notes),
        'farmId': widget.company.farmId,
        'createdBy': widget.session.tokens.userId,
      });
      if (!mounted) return;
      trackerToast(
        context,
        _isDraw ? 'Draw recorded' : 'Contribution recorded',
        description: _isDraw
            ? 'Cash is down. It is the owner taking funding back, not a business expense.'
            : 'Cash is up. It is funding, not revenue — it does not touch profit.',
      );
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not record', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = widget.fmt;
    final active = [for (final a in widget.accounts) if (a['isActive'] == true) a];
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Row(children: [
          Icon(_isDraw ? Icons.arrow_circle_up_outlined : Icons.arrow_circle_down_outlined,
              color: _isDraw ? _orange600 : TColors.emerald600),
          const SizedBox(width: 6),
          Flexible(child: Text(_isDraw ? 'Record Owner Draw' : 'Record Owner Contribution')),
        ]),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              _isDraw
                  ? 'Cash leaves the account. It is the owner taking funding back — it is not an operating expense and it will not reduce profit.'
                  : 'Cash arrives in the account. It is the owner funding the business — it is not a sale and it will not increase revenue.',
              style: const TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            formSection(_isDraw ? 'Draw' : 'Contribution', _isDraw ? TColors.amber600 : TColors.emerald600, [
              FilterLabel(
                'Date *',
                AppDateField(
                  value: businessDateAsDateTime(_date),
                  onChanged: (d) => setState(() => _date = d == null ? _date : isoDay(d)),
                ),
              ),
              FilterLabel(
                'Amount *',
                AppInput(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                  onChanged: (_) => setState(() {}),
                ),
              ),
              FilterLabel(
                'Cash account *',
                AppSelect<String>(
                  value: _account.isEmpty ? null : _account,
                  hintText: _isDraw ? 'Which account does it leave?' : 'Which account does it arrive in?',
                  items: [
                    for (final a in active)
                      AppSelectItem(
                        value: tStr(a['poultryCashAccountId']),
                        label: '${tStr(a['accountName'])} — ${fmt(tNum(a['currentBalance']))}',
                      ),
                  ],
                  onChanged: (v) => setState(() => _account = v ?? ''),
                ),
              ),
            ]),
            if (_account.isNotEmpty && _amountNum > 0) ...[
              const SizedBox(height: 12),
              formSection('After this', TColors.slate600, [
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const Expanded(child: Text('Account balance', style: TextStyle(fontSize: 13, color: TColors.slate500))),
                    Flexible(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: fmt(_balance), style: const TextStyle(color: TColors.slate400)),
                          const TextSpan(text: ' → '),
                          TextSpan(
                            text: fmt(_after),
                            style: TextStyle(fontWeight: FontWeight.w500, color: _after < 0 ? TColors.rose600 : TColors.slate900),
                          ),
                        ]),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ]),
                  if (_wouldOverdraw)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'This would take the account below zero, and it is not allowed to go negative. The draw will be rejected.',
                        style: TextStyle(fontSize: 12, color: TColors.rose600),
                      ),
                    ),
                ]),
              ]),
            ],
            const SizedBox(height: 12),
            formSection('Details', TColors.slate600, [
              FilterLabel('Owner', AppInput(controller: _owner, hintText: 'Whose money is this?')),
              FilterLabel(
                'Method',
                AppSelect<String>(
                  value: _method,
                  items: [for (final m in ownerPaymentMethods) AppSelectItem(value: m, label: m)],
                  onChanged: (v) => setState(() => _method = v ?? 'Cash'),
                ),
              ),
              FilterLabel('Reference', AppInput(controller: _ref, hintText: 'Bank or MoMo reference')),
              FilterLabel('Notes', AppInput(controller: _notes, minLines: 2, maxLines: 4)),
            ]),
          ]),
        ),
        actions: [
          redCancelButton(_saving ? null : () => Navigator.pop(context, false)),
          FilledButton(
            onPressed: _saving || _wouldOverdraw ? null : _save,
            child: Text(_saving ? 'Recording...' : _isDraw ? 'Record Draw' : 'Record Contribution'),
          ),
        ],
      ),
    );
  }
}

/// Append-only: one opposite cash row, the original kept, the reason audited.
class ReverseOwnerMoneyDialog extends StatefulWidget {
  const ReverseOwnerMoneyDialog({
    super.key,
    required this.session,
    required this.company,
    required this.row,
    required this.fmt,
    required this.when,
  });
  final Session session;
  final Company company;
  final Map row;
  final FarmMoney fmt;
  final String when;

  @override
  State<ReverseOwnerMoneyDialog> createState() => _ReverseOwnerMoneyDialogState();
}

class _ReverseOwnerMoneyDialogState extends State<ReverseOwnerMoneyDialog> {
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _reverse() async {
    final r = widget.row;
    if (_reason.text.trim().length < 3) {
      trackerToast(context, 'Say why', description: 'The reason is written to the audit trail.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post(
        '/api/Poultry/owner-money/${tStr(r['poultryOwnerMoneyId'])}/reverse',
        query: {'farmId': widget.company.farmId, 'reversedBy': widget.session.tokens.userId ?? ''},
        body: {'reason': _reason.text.trim()},
      );
      if (!mounted) return;
      trackerToast(context, 'Reversed', description: '${widget.fmt(tNum(r['amount']))} put back.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not reverse', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final num = tStr(r['transactionNumber']).isNotEmpty ? tStr(r['transactionNumber']) : '#${tStr(r['poultryOwnerMoneyId'])}';
    final acc = tStr(r['accountName']);
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const Row(children: [
          Icon(Icons.undo, color: TColors.amber600),
          SizedBox(width: 6),
          Flexible(child: Text('Reverse Owner Money')),
        ]),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              'The original stays on the record. One opposite cash row is added, putting the account back where it was, and the record stops counting towards owner funding.',
              style: TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            formSection('Record being reversed', TColors.slate600, [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$num · ${tStr(r['transactionType'])}', style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text('${widget.fmt(tNum(r['amount']))} on ${widget.when}${acc.isNotEmpty ? ' · $acc' : ''}'),
                const SizedBox(height: 8),
                Text(
                  tStr(r['transactionType']) == 'Contribution'
                      ? 'The money comes back out of the account. If it has since been spent and the account cannot go negative, the reversal will be refused.'
                      : 'The money goes back into the account.',
                  style: const TextStyle(fontSize: 12, color: TColors.slate500),
                ),
              ]),
            ]),
            const SizedBox(height: 12),
            formSection('Why', TColors.amber600, [
              FilterLabel('Reason *',
                  AppInput(controller: _reason, hintText: 'Why is this being reversed?', minLines: 3, maxLines: 5)),
              const Text('Written to the audit trail.', style: TextStyle(fontSize: 11, color: TColors.slate500)),
            ]),
          ]),
        ),
        actions: [
          redCancelButton(_saving ? null : () => Navigator.pop(context, false)),
          FilledButton(
            onPressed: _saving ? null : _reverse,
            style: FilledButton.styleFrom(backgroundColor: TColors.red600, foregroundColor: Colors.white),
            child: Text(_saving ? 'Reversing...' : 'Reverse'),
          ),
        ],
      ),
    );
  }
}
