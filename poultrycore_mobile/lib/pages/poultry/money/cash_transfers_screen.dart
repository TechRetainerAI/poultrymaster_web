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
import '../reports/report_routes.dart' show openAppHref;
import '../sales/balances_logic.dart' show entryTimestamp, pageSlice;
import '../sales/balances_widgets.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr;
import '../trackers/tracker_widgets.dart';
import 'money_widgets.dart';

/// Poultry → Money → Cash Transfers, as `app/poultry-cash-transfers/page.tsx`:
/// money moved between the farm's own accounts. It is the same money in a
/// different box — never money in or out on Cash Flow.

const transferStatusFilters = ['All', 'Approved', 'Draft', 'Reversed', 'Cancelled'];

const _sky600 = Color(0xFF0284C7);

(Color, Color) transferStatusTone(String s) => switch (s) {
      'Approved' => (TColors.emerald100, TColors.emerald800),
      'Reversed' => (TColors.amber100, TColors.amber800),
      'Cancelled' => (TColors.slate100, TColors.slate700),
      _ => (TColors.sky100, TColors.sky800),
    };

String transferNumber(Map t) =>
    tStr(t['transferNumber']).isNotEmpty ? tStr(t['transferNumber']) : '#${tStr(t['poultryCashTransferId'])}';

/// Status, then filterByDateAndSearch on transferDate and five search keys.
List<Map> filterTransfers(List<Map> rows, {String status = 'All', String search = '', String from = '', String to = ''}) {
  final s = search.trim().toLowerCase();
  return rows.where((r) {
    if (status != 'All' && tStr(r['status']) != status) return false;
    final day = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(tStr(r['transferDate']))?[1];
    if (day != null) {
      if (from.isNotEmpty && day.compareTo(from) < 0) return false;
      if (to.isNotEmpty && day.compareTo(to) > 0) return false;
    }
    if (s.isNotEmpty &&
        !['transferNumber', 'fromAccountName', 'toAccountName', 'referenceNumber', 'notes']
            .any((k) => r[k] != null && '${r[k]}'.toLowerCase().contains(s))) {
      return false;
    }
    return true;
  }).toList();
}

/// The five figures. Only approved transfers moved money; totals say "moved".
({num today, int todayCount, num month, int monthCount, int approved, (String, num)? topFrom, (String, num)? topTo}) transferStats(
    List<Map> rows,
    {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = n.toUtc().toIso8601String().substring(0, 10);
  final monthStart = DateTime(n.year, n.month, 1).toUtc().toIso8601String().substring(0, 10);
  final live = [for (final r in rows) if (tStr(r['status']) == 'Approved') r];
  final t = [for (final r in live) if (tStr(r['transferDate']).length >= 10 && tStr(r['transferDate']).substring(0, 10) == today) r];
  final m = [for (final r in live) if (tStr(r['transferDate']).compareTo(monthStart) >= 0) r];
  num sum(List<Map> xs) => xs.fold<num>(0, (s, r) => s + tNum(r['amount']));
  (String, num)? busiest(String key) {
    final tally = <String, num>{};
    for (final r in live) {
      final k = r[key] == null ? '—' : tStr(r[key]);
      tally[k] = (tally[k] ?? 0) + tNum(r['amount']);
    }
    if (tally.isEmpty) return null;
    final top = tally.entries.reduce((a, b) => b.value > a.value ? b : a);
    return (top.key, top.value);
  }

  return (
    today: sum(t),
    todayCount: t.length,
    month: sum(m),
    monthCount: m.length,
    approved: live.length,
    topFrom: busiest('fromAccountName'),
    topTo: busiest('toAccountName'),
  );
}

class CashTransfersScreen extends StatefulWidget {
  const CashTransfersScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<CashTransfersScreen> createState() => _CashTransfersScreenState();
}

class _CashTransfersScreenState extends State<CashTransfersScreen> {
  List<Map> _accounts = [], _rows = [];
  bool _loading = true;
  String _status = 'All';
  final _search = TextEditingController();
  String _from = '', _to = '';
  int _page = 1, _pageSize = 10, _lastTotal = -1;
  FarmMoney _fmt = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;

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
      final q = {'farmId': widget.company.farmId};
      final r = await Future.wait([_api.get('/api/Poultry/cash-accounts', query: q), _api.get('/api/Poultry/cash-transfers', query: q)]);
      if (!mounted) return;
      setState(() {
        _accounts = rowsOf(r[0]);
        _rows = rowsOf(r[1]);
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load transfers', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  String _when(Map t) => fmtDateTime(t['transferDate'], t, _offset);
  String _dash(Object? v) => tStr(v).isEmpty ? '–' : tStr(v);

  Future<void> _dialog(Widget d) async {
    final done = await showDialog<bool>(context: context, builder: (_) => d);
    if (done == true) _load();
  }

  Widget _reverseButton(Map t) => OutlinedButton.icon(
        onPressed: () => _dialog(ReverseTransferDialog(session: widget.session, company: widget.company, transfer: t, fmt: _fmt, when: _when(t))),
        icon: const Icon(Icons.undo, size: 16),
        label: const Text('Reverse'),
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-cash-transfers');
    final visible = filterTransfers(_rows, status: _status, search: _search.text, from: _from, to: _to);
    if (visible.length != _lastTotal) {
      _lastTotal = visible.length;
      _page = 1;
    }
    final pageRows = pageSlice(visible, _page, _pageSize);
    final st = transferStats(_rows);

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Cash Transfers')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.swap_horiz, size: 24, color: _sky600),
              SizedBox(width: 8),
              Expanded(child: Text('Cash Transfers', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            const SizedBox(height: 4),
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text(
                "Move money between the farm's own cash accounts. A transfer is the same money in a different box — it never counts as money in or money out on ",
                style: TextStyle(fontSize: 13, color: TColors.slate500),
              ),
              InkWell(
                onTap: () => openAppHref(context, widget.session, widget.company, '/cash-flow', label: 'Cash Flow'),
                child: const Text('Cash Flow', style: TextStyle(fontSize: 13, color: Color(0xFF0369A1))),
              ),
              const Text('.', style: TextStyle(fontSize: 13, color: TColors.slate500)),
            ]),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _dialog(RecordTransferDialog(session: widget.session, company: widget.company, accounts: _accounts, fmt: _fmt)),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Record transfer'),
              ),
            ),
            const SizedBox(height: 14),
            twoUp([
              moneyStat('Moved today', _fmt(st.today), hint: '${st.todayCount} transfer(s)'),
              moneyStat('Moved this month', _fmt(st.month), hint: '${st.monthCount} transfer(s)'),
              moneyStat('Transfers on record', '${_rows.length}', hint: '${st.approved} approved'),
              moneyStat('Most used source', st.topFrom?.$1 ?? '—', hint: st.topFrom == null ? null : _fmt(st.topFrom!.$2)),
              moneyStat('Most used destination', st.topTo?.$1 ?? '—', hint: st.topTo == null ? null : _fmt(st.topTo!.$2)),
            ]),
            const SizedBox(height: 14),
            ListFiltersCard(
              search: _search,
              searchPlaceholder: 'Search number, account, reference or note',
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
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in transferStatusFilters) filterChipButton(s, _status == s, () => setState(() => _status = s)),
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
                  _rows.isEmpty ? 'No transfers yet. Record one when you move money between accounts.' : 'No transfers match these filters.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: TColors.slate500),
                ),
              )
            else
              MobileCardList<Map>(
                striped: true,
                items: pageRows,
                keyOf: (t) => tStr(t['poultryCashTransferId']),
                primary: transferNumber,
                secondary: (t) => '${_when(t)} · ${tStr(t['fromAccountName'])} → ${tStr(t['toAccountName'])}',
                trailing: (t) {
                  final (bg, fg) = transferStatusTone(tStr(t['status']));
                  return Padding(padding: const EdgeInsets.only(left: 6), child: TBadge(tStr(t['status']), bg: bg, fg: fg));
                },
                highlights: (t) => [Highlight('Amount', _fmt(tNum(t['amount'])))],
                details: (t) => [
                  ('From', _dash(t['fromAccountName'])),
                  ('To', _dash(t['toAccountName'])),
                  ('Reference', _dash(t['referenceNumber'])),
                  ('Notes', _dash(t['notes'])),
                  ('Recorded by', _dash(t['createdBy'])),
                  if (tStr(t['status']) == 'Reversed') ('Reversed', _dash(t['reversalReason'])),
                ],
                actions: (t) => [if (tStr(t['status']) == 'Approved') _reverseButton(t)],
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Date', width: 140),
                    TCol('Transfer #', width: 120),
                    TCol('From', width: 130),
                    TCol('To', width: 130),
                    TCol('Amount', right: true, width: 120),
                    TCol('Reference', width: 120),
                    TCol('Recorded by', width: 120),
                    TCol('Status', width: 160),
                    TCol('', width: 120),
                  ],
                  rows: [
                    for (final t in items)
                      [
                        cellText(_when(t)),
                        Text(transferNumber(t), style: const TextStyle(fontWeight: FontWeight.w500)),
                        cellText(_dash(t['fromAccountName'])),
                        cellText(_dash(t['toAccountName'])),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(_fmt(tNum(t['amount'])),
                              style: tStr(t['status']) == 'Reversed'
                                  ? const TextStyle(decoration: TextDecoration.lineThrough, color: TColors.slate400)
                                  : const TextStyle(fontWeight: FontWeight.w500)),
                        ),
                        Text(_dash(t['referenceNumber']), style: const TextStyle(color: TColors.slate500)),
                        Text(_dash(t['createdBy']), style: const TextStyle(color: TColors.slate500)),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Builder(builder: (_) {
                            final (bg, fg) = transferStatusTone(tStr(t['status']));
                            return TBadge(tStr(t['status']), bg: bg, fg: fg);
                          }),
                          if (tStr(t['status']) == 'Reversed' && tStr(t['reversalReason']).isNotEmpty)
                            Text(tStr(t['reversalReason']),
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                        ]),
                        Align(
                          alignment: Alignment.centerRight,
                          child: tStr(t['status']) == 'Approved' ? _reverseButton(t) : const SizedBox.shrink(),
                        ),
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
        ),
      ),
    );
  }
}

/// Record Cash Transfer: created and approved in one step.
class RecordTransferDialog extends StatefulWidget {
  const RecordTransferDialog({super.key, required this.session, required this.company, required this.accounts, required this.fmt});
  final Session session;
  final Company company;
  final List<Map> accounts;
  final FarmMoney fmt;

  @override
  State<RecordTransferDialog> createState() => _RecordTransferDialogState();
}

class _RecordTransferDialogState extends State<RecordTransferDialog> {
  String _from = '', _to = '';
  String _date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  final _amount = TextEditingController(text: '0');
  final _ref = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_amount, _ref, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Map? _acc(String id) => widget.accounts.where((a) => tStr(a['poultryCashAccountId']) == id).firstOrNull;
  num _bal(String id) => tNum(_acc(id)?['currentBalance']);
  num get _amountNum => num.tryParse(_amount.text) ?? 0;
  num get _fromAfter => _bal(_from) - _amountNum;
  num get _toAfter => _bal(_to) + _amountNum;
  bool get _overdraw => _from.isNotEmpty && _amountNum > 0 && _fromAfter < 0 && _acc(_from)?['allowNegativeBalance'] != true;

  Future<void> _save() async {
    if (_from.isEmpty || _to.isEmpty) return trackerToast(context, 'Pick both accounts', error: true);
    if (_from == _to) return trackerToast(context, 'Pick two different accounts', error: true);
    if (_amountNum <= 0) return trackerToast(context, 'Enter an amount', error: true);
    setState(() => _saving = true);
    final api = widget.session.farmClient;
    final farmId = widget.company.farmId;
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    try {
      final res = await api.post('/api/Poultry/cash-transfers', body: {
        'fromPoultryCashAccountId': int.parse(_from),
        'toPoultryCashAccountId': int.parse(_to),
        'amount': _amountNum,
        'transferDate': entryTimestamp(_date),
        'referenceNumber': opt(_ref),
        'notes': opt(_notes),
        'farmId': farmId,
        'createdBy': widget.session.tokens.userId,
      });
      final id = res is Map ? tStr(res['poultryCashTransferId']) : '';
      await api.post('/api/Poultry/cash-transfers/$id/approve', query: {'farmId': farmId, 'approvedBy': widget.session.tokens.userId ?? ''});
      if (!mounted) return;
      trackerToast(context, 'Transfer recorded');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Transfer failed', description: e.message, error: true);
    }
  }

  Widget _preview(String label, num before, num after) => Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: TColors.slate500))),
        Flexible(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: widget.fmt(before), style: const TextStyle(color: TColors.slate400)),
              const TextSpan(text: ' → '),
              TextSpan(
                text: widget.fmt(after),
                style: TextStyle(fontWeight: FontWeight.w500, color: after < 0 ? TColors.rose600 : TColors.slate900),
              ),
            ]),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final fmt = widget.fmt;
    final active = [for (final a in widget.accounts) if (a['isActive'] == true) a];
    AppSelectItem<String> item(Map a) =>
        AppSelectItem(value: tStr(a['poultryCashAccountId']), label: '${tStr(a['accountName'])} — ${fmt(tNum(a['currentBalance']))}');
    final toOptions = [for (final a in active) if (tStr(a['poultryCashAccountId']) != _from) a];
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const Row(children: [
          Icon(Icons.swap_horiz, color: _sky600),
          SizedBox(width: 6),
          Flexible(child: Text('Record Cash Transfer')),
        ]),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              'Writes a matching pair of ledger rows — one out of the source, one into the destination. Company-wide cash flow is unaffected.',
              style: TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            formSection('Movement', _sky600, [
              FilterLabel(
                'Transfer date *',
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
                'From account *',
                AppSelect<String>(
                  value: _from.isEmpty ? null : _from,
                  hintText: 'Pick the account the money leaves',
                  items: [for (final a in active) item(a)],
                  onChanged: (v) => setState(() => _from = v ?? ''),
                ),
              ),
              FilterLabel(
                'To account *',
                AppSelect<String>(
                  value: toOptions.any((a) => tStr(a['poultryCashAccountId']) == _to) ? _to : null,
                  hintText: 'Pick the account the money arrives in',
                  items: [for (final a in toOptions) item(a)],
                  onChanged: (v) => setState(() => _to = v ?? ''),
                ),
              ),
            ]),
            if (_from.isNotEmpty && _to.isNotEmpty && _amountNum > 0) ...[
              const SizedBox(height: 12),
              formSection('After this transfer', TColors.slate600, [
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _preview('Source', _bal(_from), _fromAfter),
                  const SizedBox(height: 4),
                  _preview('Destination', _bal(_to), _toAfter),
                  if (_overdraw)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'This would take the source account below zero, and it is not allowed to go negative. The transfer will be rejected.',
                        style: TextStyle(fontSize: 12, color: TColors.rose600),
                      ),
                    ),
                ]),
              ]),
            ],
            const SizedBox(height: 12),
            formSection('Reference', TColors.slate600, [
              FilterLabel('Reference', AppInput(controller: _ref, hintText: 'Bank or MoMo reference')),
              FilterLabel('Notes', AppInput(controller: _notes, minLines: 2, maxLines: 4)),
            ]),
          ]),
        ),
        actions: [
          redCancelButton(_saving ? null : () => Navigator.pop(context, false)),
          FilledButton(
            onPressed: _saving || _overdraw ? null : _save,
            child: Text(_saving ? 'Recording...' : 'Record Transfer'),
          ),
        ],
      ),
    );
  }
}

/// Reverse Transfer: two opposite rows, both accounts put back.
class ReverseTransferDialog extends StatefulWidget {
  const ReverseTransferDialog({
    super.key,
    required this.session,
    required this.company,
    required this.transfer,
    required this.fmt,
    required this.when,
  });
  final Session session;
  final Company company;
  final Map transfer;
  final FarmMoney fmt;
  final String when;

  @override
  State<ReverseTransferDialog> createState() => _ReverseTransferDialogState();
}

class _ReverseTransferDialogState extends State<ReverseTransferDialog> {
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final t = widget.transfer;
    if (_reason.text.trim().length < 3) {
      return trackerToast(context, 'Say why', description: 'The reason is written to the audit trail.', error: true);
    }
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post(
        '/api/Poultry/cash-transfers/${tStr(t['poultryCashTransferId'])}/reverse',
        query: {'farmId': widget.company.farmId, 'reversedBy': widget.session.tokens.userId ?? ''},
        body: {'reason': _reason.text.trim()},
      );
      if (!mounted) return;
      trackerToast(context, 'Transfer reversed',
          description:
              '${widget.fmt(tNum(t['amount']))} put back on ${tStr(t['fromAccountName']).isEmpty ? 'the source account' : tStr(t['fromAccountName'])}.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not reverse', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.transfer;
    final amount = widget.fmt(tNum(t['amount']));
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const Row(children: [
          Icon(Icons.undo, color: TColors.amber600),
          SizedBox(width: 6),
          Flexible(child: Text('Reverse Transfer')),
        ]),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              'The original stays on the record. Two opposite rows are added, putting both accounts back where they were.',
              style: TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            formSection('Transfer being reversed', TColors.slate600, [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(transferNumber(t), style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
                  Text(tStr(t['fromAccountName']), style: const TextStyle(color: TColors.slate600)),
                  const Icon(Icons.arrow_forward, size: 12, color: TColors.slate600),
                  Text(tStr(t['toAccountName']), style: const TextStyle(color: TColors.slate600)),
                ]),
                const SizedBox(height: 4),
                Text('$amount on ${widget.when}'),
                const SizedBox(height: 8),
                Text(
                  '$amount comes back out of ${tStr(t['toAccountName'])} and returns to ${tStr(t['fromAccountName'])}. If the destination no longer holds it and cannot go negative, the reversal will be refused.',
                  style: const TextStyle(fontSize: 12, color: TColors.slate500),
                ),
              ]),
            ]),
            const SizedBox(height: 12),
            formSection('Why', TColors.amber600, [
              FilterLabel('Reason *', AppInput(controller: _reason, hintText: 'Why is this being reversed?', minLines: 3, maxLines: 5)),
              const Text('Written to the audit trail.', style: TextStyle(fontSize: 11, color: TColors.slate500)),
            ]),
          ]),
        ),
        actions: [
          redCancelButton(_saving ? null : () => Navigator.pop(context, false)),
          FilledButton(
            onPressed: _saving ? null : _go,
            style: FilledButton.styleFrom(backgroundColor: TColors.red600, foregroundColor: Colors.white),
            child: Text(_saving ? 'Reversing...' : 'Reverse Transfer'),
          ),
        ],
      ),
    );
  }
}
