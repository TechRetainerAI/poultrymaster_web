// Generic → Money (lib/nav/generic-nav-config.ts "money"):
//   Cash & accounts   app/generic-cash             live balances, read-only
//   Cash transfers    app/generic-cash-transfers   Draft → Approve / Cancel
//   Daily closing     app/generic-daily-closings   count cash; totals are the server's
//   Owner money       app/generic-owner-money      contributions and draws; never P&L

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart';
import '../poultry/reports/report_format.dart' show FarmMoney;
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';
import '../shared/reason_select.dart' show ReasonSelect, cashDifferenceReasons, reversalReasons;
import 'generic_customer_payments_screen.dart' show genericPaymentBadge;
import 'generic_kit.dart';
import 'generic_products_screen.dart' show genericBandAmber, genericBandBlue, genericBandIndigo, genericBandSlate, genericEmptyCard;
import 'reports/generic_report_kit.dart' show fmtMoney;

const _sky600 = Color(0xFF0284C7);

String _today() => DateTime.now().toUtc().toIso8601String().substring(0, 10);

/// filterByDateAndSearch: [keys] contain the search; [dateKey] within from–to.
List<Map> genericListFilter(List<Map> rows, List<String> keys, {String search = '', String? dateKey, String from = '', String to = ''}) {
  final q = search.trim().toLowerCase();
  return rows.where((r) {
    if (dateKey != null) {
      final day = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(tStr(r[dateKey]))?[1];
      if (day != null) {
        if (from.isNotEmpty && day.compareTo(from) < 0) return false;
        if (to.isNotEmpty && day.compareTo(to) > 0) return false;
      }
    }
    if (q.isNotEmpty && !keys.any((k) => tStr(r[k]).toLowerCase().contains(q))) return false;
    return true;
  }).toList();
}

Widget _title(IconData icon, Color color, String text) => Row(children: [
      Icon(icon, size: 24, color: color),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
    ]);

Widget _sub(String text) => Text(text, style: const TextStyle(fontSize: 13, color: TColors.slate500));

Widget _redCancel(BuildContext context, bool saving, {Object? result}) => OutlinedButton(
      onPressed: saving ? null : () => Navigator.pop(context, result),
      style: OutlinedButton.styleFrom(backgroundColor: TColors.red600, foregroundColor: Colors.white, side: BorderSide.none),
      child: const Text('Cancel'),
    );

Widget _moneyField(String label, TextEditingController c, {String? hint, bool signed = false}) => FilterLabel(
      label,
      AppInput(
        controller: c,
        hintText: hint,
        keyboardType: TextInputType.numberWithOptions(decimal: true, signed: signed),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(signed ? r'^-?\d*\.?\d{0,2}' : r'^\d*\.?\d{0,2}'))],
      ),
    );

Widget _statusButtons(List<String> statuses, String current, ValueChanged<String> pick) => Wrap(spacing: 4, runSpacing: 4, children: [
      for (final s in statuses) filterChipButton(s, s == current, () => pick(s)),
    ]);

// ------------------------------------------------------------ cash & accounts

class GenericCashScreen extends StatefulWidget {
  const GenericCashScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<GenericCashScreen> createState() => _GenericCashScreenState();
}

class _GenericCashScreenState extends State<GenericCashScreen> {
  List<Map> _rows = [];
  bool _loading = true;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = rowsOf(await widget.session.farmClient.get('${genericBase(widget.company)}/cash-accounts'));
      if (mounted) setState(() => _rows = r);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load cash accounts', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Widget _badge(Map a) =>
      a['isActive'] == true ? const TBadge('Active', bg: TColors.emerald100, fg: TColors.emerald800) : const TBadge('Inactive', bg: TColors.slate100, fg: TColors.slate900);

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/generic-cash');
    final active = _rows.where((a) => a['isActive'] == true).toList();
    final total = active.fold<num>(0, (s, a) => s + tNum(a['currentBalance']));
    final visible = genericListFilter(_rows, const ['accountName', 'accountType'], search: _search.text);
    Color? neg(Map a) => tNum(a['currentBalance']) < 0 ? TColors.rose700 : null;
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Cash & accounts')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            _title(Icons.account_balance_wallet_outlined, _sky600, 'Cash & accounts'),
            _sub('Live balances. Transfers + adjustments come in Part 2.'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('TOTAL CASH AT HAND', style: TextStyle(fontSize: 11, color: TColors.slate500)),
                const SizedBox(height: 4),
                Text(fmtMoney(total), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: TColors.slate900)),
                const SizedBox(height: 4),
                Text('across ${active.length} active account(s)', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const LoadingLine('Loading…')
            else if (_rows.isEmpty)
              genericEmptyCard('No cash accounts. Run setup to seed defaults.')
            else ...[
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
              const SizedBox(height: 14),
              MobileCardList<Map>(
                items: visible,
                keyOf: (a) => '${tIntOrNull(a['genericCashAccountId'])}',
                primary: (a) => tStr(a['accountName']),
                secondary: (a) => tStr(a['accountType']),
                trailing: (a) => Padding(padding: const EdgeInsets.only(left: 6), child: _badge(a)),
                details: (a) => [
                  ('Type', tStr(a['accountType'])),
                  ('Opening', fmtMoney(a['openingBalance'])),
                  ('Current', fmtMoney(a['currentBalance'])),
                  ('Allows negative', a['allowNegativeBalance'] == true ? 'Yes' : 'No'),
                ],
                detailColor: (a, label) => label == 'Current' ? neg(a) : null,
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Account', width: 160), TCol('Type', width: 110), TCol('Opening', right: true, width: 110),
                    TCol('Current', right: true, width: 110), TCol('Allows negative', width: 110), TCol('Status', width: 90),
                  ],
                  rows: [
                    for (final a in items)
                      [
                        Text(tStr(a['accountName']), style: const TextStyle(fontWeight: FontWeight.w500)),
                        cellText(tStr(a['accountType'])),
                        Align(alignment: Alignment.centerRight, child: Text(fmtMoney(a['openingBalance']))),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(fmtMoney(a['currentBalance']), style: TextStyle(fontWeight: FontWeight.w600, color: neg(a))),
                        ),
                        cellText(a['allowNegativeBalance'] == true ? 'Yes' : 'No'),
                        Align(alignment: Alignment.centerLeft, child: _badge(a)),
                      ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- cash transfers

const genericTransferStatuses = ['All', 'Draft', 'Approved', 'Cancelled'];

String _fromName(Map t) => tStr(t['fromAccountName']).isEmpty ? '#${tStr(t['fromGenericCashAccountId'])}' : tStr(t['fromAccountName']);
String _toName(Map t) => tStr(t['toAccountName']).isEmpty ? '#${tStr(t['toGenericCashAccountId'])}' : tStr(t['toAccountName']);

class GenericCashTransfersScreen extends StatefulWidget {
  const GenericCashTransfersScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<GenericCashTransfersScreen> createState() => _GenericCashTransfersScreenState();
}

class _GenericCashTransfersScreenState extends State<GenericCashTransfersScreen> {
  List<Map> _rows = [], _accounts = [];
  bool _loading = true;
  String _status = 'All';
  final _search = TextEditingController();
  String _from = '', _to = '';
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _base => '${genericBase(widget.company)}/cash-transfers';

  @override
  void initState() {
    super.initState();
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
      final r = await Future.wait([
        _api.get(_base, query: _status == 'All' ? null : {'status': _status}),
        _api.get('${genericBase(widget.company)}/cash-accounts'),
      ]);
      if (mounted) {
        setState(() {
          _rows = rowsOf(r[0]);
          _accounts = rowsOf(r[1]);
        });
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _create() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _TransferDialog(session: widget.session, company: widget.company, accounts: _accounts),
    );
    if (done == true) _load();
  }

  Future<void> _act(Map t, String action, String done, String failed) async {
    final id = tIntOrNull(t['genericCashTransferId']) ?? 0;
    try {
      await _api.post('$_base/$id/$action', body: {});
      if (mounted) trackerToast(context, 'Transfer #$id $done.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, failed, description: e.message, error: true);
    }
  }

  List<Widget> _actions(Map t) => tStr(t['status']) != 'Draft'
      ? const []
      : [
          OutlinedButton.icon(
            onPressed: () => _act(t, 'approve', 'approved', 'Approve failed'),
            style: OutlinedButton.styleFrom(foregroundColor: TColors.emerald700, side: const BorderSide(color: TColors.emerald200)),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Approve'),
          ),
          OutlinedButton.icon(
            onPressed: () => _act(t, 'cancel', 'cancelled', 'Cancel failed'),
            style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: TColors.red200)),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Cancel'),
          ),
        ];

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/generic-cash-transfers');
    final visible = genericListFilter(_rows, const ['fromAccountName', 'toAccountName', 'notes'],
        search: _search.text, dateKey: 'transferDate', from: _from, to: _to);
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Cash transfers')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            _title(Icons.swap_horiz, _sky600, 'Cash transfers'),
            // The web's text has a mis-encoded arrow here; the app shows the arrow it means.
            _sub('Move cash between your own accounts (Cash Box → MoMo → Bank etc.)'),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add, size: 18), label: const Text('New transfer')),
            const SizedBox(height: 12),
            _statusButtons(genericTransferStatuses, _status, (s) {
              if (s == _status) return;
              setState(() => _status = s);
              _load();
            }),
            const SizedBox(height: 12),
            if (_loading && _rows.isEmpty)
              const LoadingLine('Loading...')
            else if (_rows.isEmpty)
              genericEmptyCard('No transfers yet.')
            else ...[
              ListFiltersCard(
                search: _search,
                searchPlaceholder: 'Search from/to account or notes',
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
              const SizedBox(height: 14),
              MobileCardList<Map>(
                items: visible,
                keyOf: (t) => '${tIntOrNull(t['genericCashTransferId'])}',
                primary: (t) => '#${tStr(t['genericCashTransferId'])} · ${_fromName(t)} → ${_toName(t)}',
                secondary: (t) => fmtDateTime(t['transferDate'], t, _offset),
                trailing: (t) => Padding(padding: const EdgeInsets.only(left: 6), child: genericPaymentBadge(t['status'])),
                details: (t) => [
                  ('Date', fmtDateTime(t['transferDate'], t, _offset)),
                  ('From', _fromName(t)),
                  ('To', _toName(t)),
                  ('Amount', fmtMoney(t['amount'])),
                ],
                actions: _actions,
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('#', width: 60), TCol('Date', width: 140), TCol('From', width: 130), TCol('', width: 30), TCol('To', width: 130),
                    TCol('Amount', right: true, width: 110), TCol('Status', width: 100), TCol('', width: 220),
                  ],
                  rows: [
                    for (final t in items)
                      [
                        cellText('#${tStr(t['genericCashTransferId'])}'),
                        cellText(fmtDateTime(t['transferDate'], t, _offset)),
                        cellText(_fromName(t)),
                        const Icon(Icons.swap_horiz, size: 14, color: TColors.slate400),
                        cellText(_toName(t)),
                        Align(alignment: Alignment.centerRight, child: Text(fmtMoney(t['amount']), style: const TextStyle(fontWeight: FontWeight.w600))),
                        Align(alignment: Alignment.centerLeft, child: genericPaymentBadge(t['status'])),
                        Wrap(spacing: 4, children: _actions(t)),
                      ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TransferDialog extends StatefulWidget {
  const _TransferDialog({required this.session, required this.company, required this.accounts});
  final Session session;
  final Company company;
  final List<Map> accounts;

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  String _fromId = '', _toId = '', _date = _today();
  final _amount = TextEditingController(text: '0'), _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_fromId.isEmpty || _toId.isEmpty) return trackerToast(context, 'Pick both accounts', error: true);
    if (_fromId == _toId) return trackerToast(context, 'From and To must differ', error: true);
    final amount = num.tryParse(_amount.text) ?? 0;
    if (!(amount > 0)) return trackerToast(context, 'Amount must be greater than zero', error: true);
    setState(() => _saving = true);
    try {
      final created = await widget.session.farmClient.post('${genericBase(widget.company)}/cash-transfers', body: {
        'fromGenericCashAccountId': int.parse(_fromId),
        'toGenericCashAccountId': int.parse(_toId),
        'amount': amount,
        'transferDate': _date,
        'notes': _notes.text.isEmpty ? null : _notes.text,
        'farmId': widget.company.farmId,
      });
      if (created != null && mounted) {
        trackerToast(context, 'Transfer created as Draft. Approve to move the cash.');
        Navigator.pop(context, true);
        return;
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not create transfer', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.accounts.where((a) => a['isActive'] == true);
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const Row(children: [
          Icon(Icons.swap_horiz, size: 20, color: TColors.blue600),
          SizedBox(width: 8),
          Expanded(child: Text('New cash transfer')),
        ]),
        content: SizedBox(
          width: 512,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Creates a Draft. Approval writes paired TransferOut + TransferIn entries.', style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            formSection('Accounts', genericBandIndigo, [
              FilterLabel(
                'From *',
                AppSelect<String>(
                  value: _fromId.isEmpty ? null : _fromId,
                  hintText: 'Source...',
                  items: [
                    for (final a in active)
                      AppSelectItem(value: tStr(a['genericCashAccountId']), label: '${tStr(a['accountName'])} – ${fmtMoney(a['currentBalance'])}'),
                  ],
                  onChanged: (v) => setState(() => _fromId = v ?? ''),
                ),
              ),
              FilterLabel(
                'To *',
                AppSelect<String>(
                  value: _toId.isEmpty ? null : _toId,
                  hintText: 'Destination...',
                  items: [
                    for (final a in active)
                      if (tStr(a['genericCashAccountId']) != _fromId || tStr(a['genericCashAccountId']) == _toId)
                        AppSelectItem(value: tStr(a['genericCashAccountId']), label: tStr(a['accountName'])),
                  ],
                  onChanged: (v) => setState(() => _toId = v ?? ''),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            formSection('Transfer details', genericBandBlue, [
              _moneyField('Amount *', _amount),
              FilterLabel('Date', AppDateField(value: businessDateAsDateTime(_date), onChanged: (d) => setState(() => _date = d == null ? _date : isoDay(d)))),
            ]),
            const SizedBox(height: 12),
            formSection('Notes', genericBandSlate, [
              FilterLabel('Notes', AppInput(controller: _notes, minLines: 2, maxLines: 4, inputFormatters: [LengthLimitingTextInputFormatter(500)])),
            ]),
          ]),
        ),
        actions: [
          _redCancel(context, _saving),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Create')),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- daily closing

/// badgeClass: Approved emerald, Rejected rose, Submitted sky, else slate.
Widget genericClosingBadge(Object? status) {
  final (bg, fg) = switch (tStr(status)) {
    'Approved' => (TColors.emerald100, TColors.emerald800),
    'Rejected' => (TColors.rose100, TColors.rose800),
    'Submitted' => (TColors.sky100, TColors.sky800),
    _ => (TColors.slate100, TColors.slate800),
  };
  return TBadge(tStr(status), bg: bg, fg: fg);
}

class GenericDailyClosingsScreen extends StatefulWidget {
  const GenericDailyClosingsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<GenericDailyClosingsScreen> createState() => _GenericDailyClosingsScreenState();
}

class _GenericDailyClosingsScreenState extends State<GenericDailyClosingsScreen> {
  List<Map> _rows = [];
  bool _loading = true;
  final _search = TextEditingController();
  String _from = '', _to = '';
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _base => '${genericBase(widget.company)}/daily-closings';

  @override
  void initState() {
    super.initState();
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
      final r = rowsOf(await _api.get(_base));
      if (mounted) setState(() => _rows = r);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load closings', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _create() async {
    final done = await showDialog<bool>(context: context, builder: (_) => _ClosingDialog(session: widget.session, company: widget.company));
    if (done == true) _load();
  }

  int _id(Map c) => tIntOrNull(c['genericDailyClosingId']) ?? 0;

  Future<void> _approve(Map c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve and lock?'),
        content: const Text('Once approved, this closing becomes a frozen snapshot of the day.'),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve')),
        ],
      ),
    );
    if (ok != true) return;
    final id = _id(c);
    try {
      await _api.post('$_base/$id/approve', body: {});
      if (mounted) trackerToast(context, 'Closing #$id approved and locked.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Approve failed', description: e.message, error: true);
    }
  }

  /// Submit and Refresh are the same call: the server re-aggregates the totals.
  Future<void> _resubmit(Map c) async {
    final id = _id(c);
    try {
      await _api.post('$_base/$id/submit', body: {});
      if (mounted) trackerToast(context, 'Closing #$id re-submitted with fresh totals.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Re-submit failed', description: e.message, error: true);
    }
  }

  List<Widget> _actions(Map c) => switch (tStr(c['status'])) {
        'Submitted' => [
            OutlinedButton.icon(
              onPressed: () => _approve(c),
              style: OutlinedButton.styleFrom(foregroundColor: TColors.emerald700, side: const BorderSide(color: TColors.emerald200)),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Approve'),
            ),
            OutlinedButton.icon(onPressed: () => _resubmit(c), icon: const Icon(Icons.refresh, size: 16), label: const Text('Refresh')),
          ],
        'Draft' => [OutlinedButton(onPressed: () => _resubmit(c), child: const Text('Submit'))],
        _ => const [],
      };

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/generic-daily-closings');
    final visible = genericListFilter(_rows, const ['status', 'managerNotes'], search: _search.text, dateKey: 'closingDate', from: _from, to: _to);
    Color? diff(Map c) => tNum(c['cashDifference']) != 0 ? TColors.rose700 : null;
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Daily closings')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            _title(Icons.description_outlined, TColors.slate700, 'Daily closings'),
            _sub('${_rows.length} closing(s) — totals are auto-aggregated; you just count cash.'),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add, size: 18), label: const Text('Close today')),
            const SizedBox(height: 14),
            if (_loading)
              const LoadingLine('Loading…')
            else if (_rows.isEmpty)
              genericEmptyCard(
                '',
                child: const Text.rich(
                  TextSpan(text: 'No daily closings yet. Click ', children: [
                    TextSpan(text: 'Close today', style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: ' to count cash and submit your first one.'),
                  ]),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: TColors.slate500),
                ),
              )
            else ...[
              ListFiltersCard(
                search: _search,
                searchPlaceholder: 'Search status or manager notes',
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
              const SizedBox(height: 14),
              MobileCardList<Map>(
                items: visible,
                keyOf: (c) => '${_id(c)}',
                primary: (c) => fmtDateTime(c['closingDate'], c, _offset),
                secondary: (c) => 'Sales ${fmtMoney(c['totalSales'])} · Exp ${fmtMoney(c['totalExpenses'])}',
                trailing: (c) => Padding(padding: const EdgeInsets.only(left: 6), child: genericClosingBadge(c['status'])),
                details: (c) => [
                  ('Sales', fmtMoney(c['totalSales'])),
                  ('Expenses', fmtMoney(c['totalExpenses'])),
                  ('Expected cash', fmtMoney(c['expectedCash'])),
                  ('Actual cash', fmtMoney(c['actualCashCounted'])),
                  ('Difference', fmtMoney(c['cashDifference'])),
                ],
                detailColor: (c, label) => label == 'Difference' ? diff(c) : null,
                actions: _actions,
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Date', width: 140), TCol('Sales', right: true, width: 110), TCol('Expenses', right: true, width: 110),
                    TCol('Expected', right: true, width: 110), TCol('Actual', right: true, width: 110), TCol('Diff', right: true, width: 100),
                    TCol('Status', width: 100), TCol('', width: 220),
                  ],
                  rows: [
                    for (final c in items)
                      [
                        cellText(fmtDateTime(c['closingDate'], c, _offset)),
                        for (final k in ['totalSales', 'totalExpenses', 'expectedCash', 'actualCashCounted'])
                          Align(alignment: Alignment.centerRight, child: Text(fmtMoney(c[k]))),
                        Align(alignment: Alignment.centerRight, child: Text(fmtMoney(c['cashDifference']), style: TextStyle(color: diff(c)))),
                        Align(alignment: Alignment.centerLeft, child: genericClosingBadge(c['status'])),
                        Wrap(spacing: 4, children: _actions(c)),
                      ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ClosingDialog extends StatefulWidget {
  const _ClosingDialog({required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<_ClosingDialog> createState() => _ClosingDialogState();
}

class _ClosingDialogState extends State<_ClosingDialog> {
  String _date = _today(), _reason = '';
  final _opening = TextEditingController(), _counted = TextEditingController(text: '0'), _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_opening, _counted, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final api = widget.session.farmClient;
    final base = '${genericBase(widget.company)}/daily-closings';
    try {
      final created = await api.post(base, body: {
        'closingDate': _date,
        'openingCash': _opening.text.isEmpty ? null : (num.tryParse(_opening.text) ?? 0),
        'actualCashCounted': num.tryParse(_counted.text) ?? 0,
        'managerNotes': _notes.text.isEmpty ? null : _notes.text,
        'differenceReason': _reason.isEmpty ? null : _reason,
        'farmId': widget.company.farmId,
      });
      if (created is Map) {
        // Auto-submit so the totals are aggregated straight away.
        final id = tIntOrNull(created['genericDailyClosingId']);
        await api.post('$base/$id/submit', body: {});
        if (mounted) {
          trackerToast(context, 'Closing #$id created and submitted.', description: 'Totals aggregated automatically. Review and approve.');
          Navigator.pop(context, true);
        }
        return;
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not create closing', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const Text('Daily closing'),
        content: SizedBox(
          width: 512,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              'Enter only the cash you counted. Sales, expenses, payments and expected cash are computed automatically from the immutable ledgers.',
              style: TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            FilterLabel('Closing date', AppDateField(value: businessDateAsDateTime(_date), onChanged: (d) => setState(() => _date = d == null ? _date : isoDay(d)))),
            const SizedBox(height: 12),
            _moneyField('Opening cash (optional)', _opening, hint: 'auto', signed: true),
            const SizedBox(height: 12),
            _moneyField('Actual cash counted *', _counted),
            const SizedBox(height: 12),
            FilterLabel('Manager notes', AppInput(controller: _notes, minLines: 2, maxLines: 4, inputFormatters: [LengthLimitingTextInputFormatter(2000)])),
            const SizedBox(height: 12),
            FilterLabel(
              'Reason for any cash difference',
              ReasonSelect(options: cashDifferenceReasons, value: _reason, onChanged: (v) => setState(() => _reason = v)),
            ),
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_saving) ...[
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                const SizedBox(width: 8),
              ],
              const Flexible(child: Text('Create & submit', overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- owner money

const genericOwnerMethods = ['Cash', 'Bank', 'Mobile Money', 'Card', 'Other'];

/// Put in, taken out and net, leaving reversed entries out (the money came back).
({num inSum, num outSum, num net}) genericOwnerTotals(List<Map> rows) {
  final live = rows.where((r) => tStr(r['status']) != 'Reversed');
  final inSum = live.where((r) => tStr(r['entryType']) == 'Contribution').fold<num>(0, (s, r) => s + tNum(r['amount']));
  final outSum = live.where((r) => tStr(r['entryType']) == 'Draw').fold<num>(0, (s, r) => s + tNum(r['amount']));
  return (inSum: inSum, outSum: outSum, net: inSum - outSum);
}

class GenericOwnerMoneyScreen extends StatefulWidget {
  const GenericOwnerMoneyScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<GenericOwnerMoneyScreen> createState() => _GenericOwnerMoneyScreenState();
}

class _GenericOwnerMoneyScreenState extends State<GenericOwnerMoneyScreen> {
  List<Map> _rows = [], _accounts = [];
  bool _loading = true;
  final _search = TextEditingController();
  String _type = 'All';
  int _page = 1, _pageSize = 10, _lastTotal = -1;
  FarmMoney _fmt = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _base => '${genericBase(widget.company)}/owner-entries';

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
      final r = await Future.wait([
        _api.get(_base),
        // getCashAccounts().catch(() => []): the accounts failing is not an error here.
        _api.get('${genericBase(widget.company)}/cash-accounts').then<Object?>((v) => v, onError: (_) => <Object?>[]),
      ]);
      if (mounted) {
        setState(() {
          _rows = rowsOf(r[0]);
          _accounts = rowsOf(r[1]);
        });
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load owner money', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _record() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _OwnerDialog(session: widget.session, company: widget.company, accounts: _accounts),
    );
    if (done == true) _load();
  }

  Future<void> _reverse(Map r) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReverseOwnerDialog(
          description: '${_fmt(tNum(r['amount']))} ${tStr(r['entryType']) == 'Contribution' ? 'put in' : 'taken out'}. '
              'The cash movement is undone with an opposite entry. The original is kept and marked reversed.'),
    );
    if (reason == null) return;
    try {
      await _api.post('$_base/${tIntOrNull(r['genericOwnerEntryId'])}/reverse', body: {'reason': reason, 'farmId': widget.company.farmId});
      if (mounted) trackerToast(context, 'Reversed.', description: 'The cash movement has been undone.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not reverse it', description: e.message, error: true);
    }
  }

  Widget _badge(Map r) {
    if (tStr(r['status']) == 'Reversed') return const TBadge('Reversed', bg: TColors.slate200, fg: TColors.slate700);
    final into = tStr(r['entryType']) == 'Contribution';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: into ? TColors.emerald100 : TColors.amber100, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(into ? Icons.south_west : Icons.north_east, size: 12, color: into ? TColors.emerald800 : TColors.amber800),
        const SizedBox(width: 4),
        Text(into ? 'In' : 'Out', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: into ? TColors.emerald800 : TColors.amber800)),
      ]),
    );
  }

  List<Widget> _actions(Map r) => tStr(r['status']) == 'Reversed'
      ? const []
      : [
          OutlinedButton.icon(
            onPressed: () => _reverse(r),
            style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: TColors.red200)),
            icon: const Icon(Icons.undo, size: 16),
            label: const Text('Reverse'),
          ),
        ];

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/generic-owner-money');
    final totals = genericOwnerTotals(_rows);
    final byType = _type == 'All' ? _rows : _rows.where((r) => tStr(r['entryType']) == _type).toList();
    final visible = genericListFilter(byType, const ['ownerName', 'referenceNo', 'notes', 'cashAccountName'], search: _search.text);
    if (visible.length != _lastTotal) {
      _lastTotal = visible.length;
      _page = 1;
    }
    String dash(Object? v) => tStr(v).isEmpty ? '—' : tStr(v);
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Owner money')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            _title(Icons.account_balance_wallet_outlined, genericIndigo, 'Owner money'),
            Text.rich(
              TextSpan(text: '${_fmt(totals.inSum)} put in · ${_fmt(totals.outSum)} taken out · ', children: [
                TextSpan(text: _fmt(totals.net), style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: ' net'),
              ]),
              style: const TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: _record, icon: const Icon(Icons.add, size: 18), label: const Text('Record')),
            const SizedBox(height: 14),
            if (_loading && _rows.isEmpty)
              const LoadingLine('Loading…')
            else if (_rows.isEmpty)
              genericEmptyCard('Nothing recorded yet. Money the owner puts in or takes out belongs here rather than in sales or expenses.')
            else ...[
              ListFiltersCard(
                search: _search,
                searchPlaceholder: 'Search owner, reference or notes',
                searchOnly: true,
                onSearch: () => setState(() {}),
                from: '',
                to: '',
                onDates: (_, _) {},
                onClear: () => setState(_search.clear),
                extras: [
                  AppSelect<String>(
                    value: _type,
                    items: [for (final t in const ['All', 'Contribution', 'Draw']) AppSelectItem(value: t, label: t)],
                    onChanged: (v) => setState(() => _type = v ?? 'All'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              MobileCardList<Map>(
                items: pageSlice(visible, _page, _pageSize),
                keyOf: (r) => '${tIntOrNull(r['genericOwnerEntryId'])}',
                primary: (r) => tStr(r['entryType']) == 'Contribution' ? 'Money in' : 'Money out',
                secondary: (r) => '${_fmt(tNum(r['amount']))} · ${fmtDateTime(r['entryDate'], r, _offset)}',
                trailing: (r) => Padding(padding: const EdgeInsets.only(left: 6), child: _badge(r)),
                details: (r) => [
                  ('Owner', dash(r['ownerName'])),
                  ('Account', dash(r['cashAccountName'])),
                  ('Method', dash(r['paymentMethod'])),
                  ('Reference', dash(r['referenceNo'])),
                ],
                actions: _actions,
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Date', width: 140), TCol('Type', width: 100), TCol('Owner', width: 130), TCol('Account', width: 130),
                    TCol('Reference', width: 110), TCol('Amount', right: true, width: 120), TCol('', right: true, width: 130),
                  ],
                  rows: [
                    for (final r in items)
                      [
                        cellText(fmtDateTime(r['entryDate'], r, _offset)),
                        Align(alignment: Alignment.centerLeft, child: _badge(r)),
                        cellText(dash(r['ownerName'])),
                        cellText(dash(r['cashAccountName'])),
                        cellText(dash(r['referenceNo'])),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${tStr(r['entryType']) == 'Contribution' ? '+' : '−'}${_fmt(tNum(r['amount']))}',
                            style: TextStyle(
                                fontWeight: FontWeight.w500, color: tStr(r['entryType']) == 'Contribution' ? TColors.emerald700 : TColors.amber700),
                          ),
                        ),
                        Wrap(alignment: WrapAlignment.end, children: _actions(r)),
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

class _OwnerDialog extends StatefulWidget {
  const _OwnerDialog({required this.session, required this.company, required this.accounts});
  final Session session;
  final Company company;
  final List<Map> accounts;

  @override
  State<_OwnerDialog> createState() => _OwnerDialogState();
}

class _OwnerDialogState extends State<_OwnerDialog> {
  String _type = 'Contribution', _accountId = '', _date = _today(), _method = 'Bank';
  final _amount = TextEditingController(text: '0'), _owner = TextEditingController();
  final _reference = TextEditingController(), _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_amount, _owner, _reference, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_accountId.isEmpty) {
      return trackerToast(context, 'Pick a cash account',
          description: 'Owner money always moves cash, so it has to come from or go to somewhere.', error: true);
    }
    final amount = num.tryParse(_amount.text) ?? 0;
    if (amount <= 0) return trackerToast(context, 'The amount must be more than zero', error: true);
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('${genericBase(widget.company)}/owner-entries', body: {
        'entryType': _type,
        'amount': amount,
        'cashAccountId': int.parse(_accountId),
        'entryDate': _date.isEmpty ? null : '${_date}T00:00:00Z',
        'paymentMethod': _method,
        'ownerName': _owner.text.isEmpty ? null : _owner.text,
        'reference': _reference.text.isEmpty ? null : _reference.text,
        'notes': _notes.text.isEmpty ? null : _notes.text,
        'farmId': widget.company.farmId,
      });
      if (mounted) {
        trackerToast(context, _type == 'Contribution' ? 'Contribution recorded.' : 'Draw recorded.',
            description: 'Cash moved. This does not affect profit.');
        Navigator.pop(context, true);
      }
      return;
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not record it', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const Row(children: [
          Icon(Icons.account_balance_wallet_outlined, size: 20, color: TColors.blue600),
          SizedBox(width: 8),
          Expanded(child: Text('Owner money')),
        ]),
        content: SizedBox(
          width: 640,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              'This moves cash and nothing else. It is not sales income and not a business expense, so it will not change your profit.',
              style: TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            formSection('What happened', genericBandIndigo, [
              FilterLabel(
                'Type *',
                AppSelect<String>(
                  value: _type,
                  items: const [
                    AppSelectItem(value: 'Contribution', label: 'Contribution — the owner put money in'),
                    AppSelectItem(value: 'Draw', label: 'Draw — the owner took money out'),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
              ),
              _moneyField('Amount *', _amount, signed: true),
              FilterLabel('Date', AppDateField(value: businessDateAsDateTime(_date), onChanged: (d) => setState(() => _date = d == null ? _date : isoDay(d)))),
              FilterLabel('Owner', AppInput(controller: _owner, inputFormatters: [LengthLimitingTextInputFormatter(120)])),
            ]),
            const SizedBox(height: 12),
            formSection('Which account', genericBandAmber, [
              FilterLabel(
                'Cash account *',
                AppSelect<String>(
                  value: _accountId.isEmpty ? null : _accountId,
                  hintText: 'Pick one',
                  items: [
                    for (final a in widget.accounts.where((a) => a['isActive'] == true))
                      AppSelectItem(value: tStr(a['genericCashAccountId']), label: tStr(a['accountName'])),
                  ],
                  onChanged: (v) => setState(() => _accountId = v ?? ''),
                ),
              ),
              FilterLabel(
                'Method',
                AppSelect<String>(
                  value: _method,
                  items: [for (final m in genericOwnerMethods) AppSelectItem(value: m, label: m)],
                  onChanged: (v) => setState(() => _method = v ?? _method),
                ),
              ),
              FilterLabel('Reference', AppInput(controller: _reference, inputFormatters: [LengthLimitingTextInputFormatter(60)])),
            ]),
            const SizedBox(height: 12),
            formSection('Notes', genericBandSlate, [
              FilterLabel('Notes', AppInput(controller: _notes, minLines: 2, maxLines: 4)),
            ]),
          ]),
        ),
        actions: [
          _redCancel(context, _saving, result: false),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Record')),
        ],
      ),
    );
  }
}

/// "Reverse this entry?" with the shared reversal reasons. Pops the reason.
class _ReverseOwnerDialog extends StatefulWidget {
  const _ReverseOwnerDialog({required this.description});
  final String description;

  @override
  State<_ReverseOwnerDialog> createState() => _ReverseOwnerDialogState();
}

class _ReverseOwnerDialogState extends State<_ReverseOwnerDialog> {
  String _reason = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: const Text('Reverse this entry?'),
        content: SizedBox(
          width: 448,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.description, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            ReasonSelect(options: reversalReasons, value: _reason, onChanged: (v) => setState(() => _reason = v)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep it')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TColors.red600, foregroundColor: Colors.white),
            onPressed: () {
              if (_reason.trim().isEmpty) return trackerToast(context, 'A reason is required to reverse', error: true);
              Navigator.pop(context, _reason.trim());
            },
            child: const Text('Reverse it'),
          ),
        ],
      );
}
