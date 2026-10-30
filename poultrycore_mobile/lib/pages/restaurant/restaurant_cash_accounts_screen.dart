// Restaurant → Money → Cash Account, as `app/restaurant-cash-accounts/page.tsx`:
// every place the restaurant keeps money (tills, cash box / safe, petty cash,
// mobile money, bank) with its balance, ledger and cash counts.
// API: /Restaurant/finance/accounts and /counts (migration 323).

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
import 'reports/restaurant_money_report_defs.dart' show ledgerSourceLabel;
import 'restaurant_money_kit.dart';
import 'restaurant_roles.dart' show restaurantRose;
import 'restaurant_widgets.dart';

const restaurantAccountTypes = ['Till', 'CashBox', 'PettyCash', 'MobileMoney', 'Bank', 'Other'];
const restaurantAccountTypeLabels = {
  'Till': 'Till (cash drawer)',
  'CashBox': 'Cash box / safe',
  'PettyCash': 'Petty cash',
  'MobileMoney': 'Mobile money',
  'Bank': 'Bank account',
  'Other': 'Other',
};
const restaurantDefaultForLabels = {
  'Cash': 'Cash payments',
  'Bank': 'Card, bank transfer & cheque',
  'MobileMoney': 'Mobile money',
};
const _none = '__none__';

String _typeLabel(Object? t) => restaurantAccountTypeLabels[tStr(t)] ?? tStr(t);
String _defaultForLabel(Object? d) => restaurantDefaultForLabels[tStr(d)] ?? tStr(d);
bool _outOfSync(Map a) => (tNum(a['ledgerBalance']) - tNum(a['currentBalance'])).abs() > 0.005;
bool _tillLocked(Map a) => a['accountType'] == 'Till' && tIntOrNull(a['openShiftId']) != null;
String _firstOfMonth() => '${rTodayIso().substring(0, 8)}01';

class RestaurantCashAccountsScreen extends StatefulWidget {
  const RestaurantCashAccountsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantCashAccountsScreen> createState() => _RestaurantCashAccountsScreenState();
}

class _RestaurantCashAccountsScreenState extends State<RestaurantCashAccountsScreen> {
  bool _loading = true;
  List<Map> _accounts = [];
  List<Map> _counts = [];
  String _tab = 'accounts';
  int _aPage = 1, _aSize = 10, _cPage = 1, _cSize = 10;
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
      final r = await Future.wait([loadRestaurantAccounts(_api, _farmId), _api.get(rFin('/counts', _farmId))]);
      if (!mounted) return;
      setState(() {
        _accounts = r[0] as List<Map>;
        _counts = rowsOf(r[1]);
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Error loading cash accounts', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _go(String href, String label) => openAppHref(context, widget.session, widget.company, href, label: label);

  Future<void> _account([Map? editing]) async {
    final done = await showDialog<bool>(context: context, builder: (_) => _AccountDialog(api: _api, farmId: _farmId, editing: editing));
    if (done == true) _load();
  }

  Future<void> _ledger(Map a) =>
      showDialog<void>(context: context, builder: (_) => _LedgerDialog(api: _api, farmId: _farmId, account: a, gh: _gh));

  Future<void> _count(Map a) async {
    final done = await showDialog<bool>(context: context, builder: (_) => _CountDialog(api: _api, farmId: _farmId, account: a, gh: _gh));
    if (done == true) _load();
  }

  Future<void> _reverseCount(Map c) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => RReasonDialog(
        title: 'Reverse count',
        description:
            '${tStr(c['accountName'])}, ${tStr(c['countDate']).length >= 10 ? tStr(c['countDate']).substring(0, 10) : tStr(c['countDate'])} — the difference of ${_gh(tNum(c['difference']))} will be undone.',
        options: cashCountReversalReasons,
        keepLabel: 'Cancel',
        confirmLabel: 'Reverse',
        busyLabel: 'Reversing...',
        errorTitle: 'Could not reverse count',
        destructive: false,
        missingReason: ('Reason required', 'Say why this count is being reversed.'),
        submit: (reason) => _api.post(rFin('/counts/${tIntOrNull(c['countId'])}/reverse', _farmId), body: {'reason': reason}),
      ),
    );
    if (done == true) {
      if (mounted) trackerToast(context, 'Count reversed');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-cash-accounts');
    Widget body;
    if (!_canView) {
      body = const TCard(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Text('You do not have access to Cash Accounts.', style: TextStyle(color: TColors.slate600))),
        ),
      );
    } else if (_loading) {
      body = const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: LoadingLine('Loading…')));
    } else {
      final active = [for (final a in _accounts) if (a['isActive'] == true) a];
      final total = active.fold<num>(0, (s, a) => s + tNum(a['currentBalance']));
      final belowZero = _accounts.where((a) => tNum(a['currentBalance']) < 0).length;
      final openShifts = _accounts.where((a) => tIntOrNull(a['openShiftId']) != null).length;
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const RPageHeader(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Cash Account',
          subtitle: 'Tills, cash box, petty cash, mobile money and bank — with their balances',
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
              onPressed: () => _go('/restaurant-cash-reconciliation', 'Reconciliation'),
              icon: const Icon(Icons.balance, size: 16),
              label: const Text('Reconcile')),
          OutlinedButton.icon(
              onPressed: () => _go('/restaurant-reports/cash-accounts', 'Cash Account Report'),
              icon: const Icon(Icons.description_outlined, size: 16),
              label: const Text('Cash Account Report')),
          OutlinedButton.icon(
              onPressed: () => _go('/restaurant-cash-transfers', 'Cash Transfers'),
              icon: const Icon(Icons.swap_horiz, size: 16),
              label: const Text('Transfer')),
          roseButton('New account', () => _account()),
        ]),
        const SizedBox(height: 8),
        const Text('Every payment, expense, transfer and till shift posts here automatically. The three default accounts are created for you.',
            style: TextStyle(fontSize: 13, color: TColors.slate500)),
        const SizedBox(height: 14),
        twoColumns([
          _tile('Total cash at hand', _gh(total), 'violet'),
          _tile('Active accounts', '${active.length}', 'emerald'),
          _tile('Open till shifts', '$openShifts', 'amber'),
          _tile('Accounts below zero', '$belowZero', belowZero > 0 ? 'rose' : 'blue'),
        ], gap: 12),
        const SizedBox(height: 16),
        Container(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate200))),
          child: Wrap(children: [
            for (final (k, l) in [('accounts', 'Accounts'), ('counts', 'Count history')])
              InkWell(
                onTap: () => setState(() => _tab = k),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: _tab == k ? Colors.white : null,
                    border: _tab == k ? Border.all(color: TColors.slate200) : null,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                  child: Text(l,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _tab == k ? const Color(0xFFE11D48) : TColors.slate500)),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        if (_tab == 'accounts') _accountsTab() else _countsTab(),
      ]);
    }
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Cash Account')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [body]),
      ),
    );
  }

  static const _tileTones = {
    'violet': (Color(0xFFEDE9FE), Color(0xFFC4B5FD), Color(0xFF4C1D95), Color(0xFF4C1D95)),
    'emerald': (TColors.emerald100, TColors.emerald300, TColors.emerald900, TColors.emerald800),
    'amber': (Color(0xFFFEF3C7), TColors.amber300, TColors.amber900, Color(0xFF92400E)),
    'blue': (TColors.blue100, TColors.blue300, TColors.blue900, Color(0xFF1E40AF)),
    'rose': (Color(0xFFFFE4E6), Color(0xFFFDA4AF), Color(0xFF881337), TColors.rose800),
  };

  /// Poultry's coloured cash-account tile.
  Widget _tile(String label, String value, String accent) {
    final (bg, border, labelFg, valueFg) = _tileTones[accent]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .5, color: labelFg)),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: valueFg)),
      ]),
    );
  }

  Widget _accountsTab() {
    if (_accounts.isEmpty) {
      return TCard(
        child: REmptyState(
          icon: Icons.account_balance_wallet_outlined,
          title: 'No cash accounts yet',
          description: 'Add the places where the restaurant keeps money.',
          actionLabel: 'New account',
          onAction: () => _account(),
        ),
      );
    }
    return TCard(
      padding: const EdgeInsets.all(10),
      child: MobileCardList<Map>(
        items: pageSlice(_accounts, _aPage, _aSize),
        striped: true,
        keyOf: (a) => '${a['cashAccountId']}',
        primary: (a) => tStr(a['name']),
        secondary: (a) =>
            '${_typeLabel(a['accountType'])}${tStr(a['defaultFor']).isNotEmpty ? ' · default for ${_defaultForLabel(a['defaultFor'])}' : ''}',
        trailing: (a) => a['isActive'] == true ? null : rStatusBadge('Inactive', fg: TColors.slate500),
        highlights: (a) => [
          Highlight('Balance', _gh(tNum(a['currentBalance'])), accent: tNum(a['currentBalance']) < 0 ? Accent.rose : Accent.violet, wide: true),
        ],
        details: (a) => [
          (
            'Last counted',
            tStr(a['lastCountedAt']).isNotEmpty
                ? '${tStr(a['lastCountedAt']).substring(0, 10)}${a['lastCountedBalance'] != null ? ' at ${_gh(tNum(a['lastCountedBalance']))}' : ''}'
                : 'Never counted'
          ),
          (
            'Open shift',
            tIntOrNull(a['openShiftId']) != null
                ? (tStr(a['openShiftNumber']).isNotEmpty ? tStr(a['openShiftNumber']) : 'SH-${a['openShiftId']}')
                : '—'
          ),
          if (_outOfSync(a)) ('Out of sync', 'Ledger says ${_gh(tNum(a['ledgerBalance']))}'),
        ],
        actions: (a) => [
          OutlinedButton.icon(onPressed: () => _ledger(a), icon: const Icon(Icons.menu_book_outlined, size: 16), label: const Text('View details')),
          OutlinedButton.icon(
              onPressed: _tillLocked(a) ? null : () => _count(a), icon: const Icon(Icons.calculate_outlined, size: 16), label: const Text('Count')),
          OutlinedButton.icon(onPressed: () => _account(a), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
        ],
        // The web passes no table for accounts on a phone.
        table: (_) => const SizedBox.shrink(),
        pager: CompactPager(
          total: _accounts.length,
          page: _aPage,
          pageSize: _aSize,
          onPage: (p) => setState(() => _aPage = p),
          onPageSize: (v) => setState(() {
            _aSize = v;
            _aPage = 1;
          }),
        ),
      ),
    );
  }

  String _diffText(num d) => '${d > 0 ? '+' : ''}${_gh(d)}${d > 0 ? ' over' : d < 0 ? ' short' : ''}';

  Widget _countsTab() {
    if (_counts.isEmpty) {
      return const TCard(
        child: REmptyState(icon: Icons.calculate_outlined, title: 'No counts yet', description: 'Use Count on an account to confirm what is really there.'),
      );
    }
    return TCard(
      padding: const EdgeInsets.all(10),
      child: MobileCardList<Map>(
        items: pageSlice(_counts, _cPage, _cSize),
        striped: true,
        keyOf: (c) => '${c['countId']}',
        primary: (c) => tStr(c['accountName']),
        secondary: (c) => tStr(c['countDate']).length >= 10 ? tStr(c['countDate']).substring(0, 10) : tStr(c['countDate']),
        trailing: (c) => c['status'] == 'Posted'
            ? rStatusBadge('Posted', bg: const Color(0xFFDCFCE7), fg: const Color(0xFF166534), border: const Color(0xFFBBF7D0))
            : rStatusBadge(tStr(c['status']), bg: TColors.slate100, fg: TColors.slate600),
        highlights: (c) {
          final d = tNum(c['difference']);
          return [
            Highlight('Difference', _diffText(d), accent: d > 0 ? Accent.emerald : d < 0 ? Accent.rose : Accent.slate, wide: true),
            Highlight('System', _gh(tNum(c['systemBalance']))),
            Highlight('Counted', _gh(tNum(c['countedBalance'])), accent: Accent.blue),
          ];
        },
        details: (c) => [
          ('Notes', tStr(c['notes']).isEmpty ? '—' : tStr(c['notes'])),
          if (tStr(c['reversalReason']).isNotEmpty) ('Reversed', tStr(c['reversalReason'])),
        ],
        actions: (c) => c['status'] == 'Posted'
            ? [OutlinedButton.icon(onPressed: () => _reverseCount(c), icon: const Icon(Icons.undo, size: 16), label: const Text('Reverse'))]
            : [],
        table: (rows) => TrackerTable(
          columns: const [
            TCol('Date', width: 100),
            TCol('Account', width: 160),
            TCol('System', right: true, width: 110),
            TCol('Counted', right: true, width: 110),
            TCol('Difference', right: true, width: 140),
            TCol('Status', width: 150),
            TCol('Actions', right: true, width: 110),
          ],
          rows: [
            for (final c in rows)
              () {
                final d = tNum(c['difference']);
                return [
                  cellText(tStr(c['countDate']).length >= 10 ? tStr(c['countDate']).substring(0, 10) : tStr(c['countDate']), color: TColors.slate500),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(tStr(c['accountName']), style: const TextStyle(fontWeight: FontWeight.w500)),
                    if (tStr(c['notes']).isNotEmpty) Text(tStr(c['notes']), style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                  ]),
                  cellText(_gh(tNum(c['systemBalance']))),
                  cellText(_gh(tNum(c['countedBalance']))),
                  cellText(_diffText(d), color: d > 0 ? const Color(0xFF16A34A) : d < 0 ? TColors.red600 : TColors.slate700, bold: true),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    c['status'] == 'Posted'
                        ? rStatusBadge('Posted', bg: const Color(0xFFDCFCE7), fg: const Color(0xFF166534), border: const Color(0xFFBBF7D0))
                        : rStatusBadge(tStr(c['status']), bg: TColors.slate100, fg: TColors.slate600),
                    if (c['status'] != 'Posted' && tStr(c['reversalReason']).isNotEmpty)
                      Text(tStr(c['reversalReason']), style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                  ]),
                  c['status'] == 'Posted'
                      ? OutlinedButton.icon(onPressed: () => _reverseCount(c), icon: const Icon(Icons.undo, size: 16), label: const Text('Reverse'))
                      : const SizedBox(),
                ];
              }(),
          ],
        ),
        pager: CompactPager(
          total: _counts.length,
          page: _cPage,
          pageSize: _cSize,
          onPage: (p) => setState(() => _cPage = p),
          onPageSize: (v) => setState(() {
            _cSize = v;
            _cPage = 1;
          }),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ New / Edit account

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({required this.api, required this.farmId, this.editing});
  final ApiClient api;
  final String farmId;
  final Map? editing;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final Map? _e = widget.editing;
  late final _name = TextEditingController(text: _e == null ? '' : tStr(_e['name']));
  final _opening = TextEditingController();
  late final _notes = TextEditingController(text: _e == null ? '' : tStr(_e['notes']));
  late String _type = _e == null ? 'CashBox' : tStr(_e['accountType']);
  late String _defaultFor = _e == null || tStr(_e['defaultFor']).isEmpty ? _none : tStr(_e['defaultFor']);
  late bool _allowNegative = _e?['allowNegative'] == true;
  late bool _isActive = _e == null ? true : _e['isActive'] == true;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _opening, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      trackerToast(context, 'Name required', description: 'Give the account a name.', error: true);
      return;
    }
    final defaultFor = _defaultFor == _none ? null : _defaultFor;
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    num? opening;
    if (_e == null && _opening.text.trim().isNotEmpty) {
      opening = num.tryParse(_opening.text.trim());
      if (opening == null) {
        trackerToast(context, 'Invalid opening balance', description: 'Enter a number or leave it blank.', error: true);
        return;
      }
    }
    setState(() => _saving = true);
    try {
      if (_e != null) {
        await widget.api.put(rFin('/accounts/${tIntOrNull(_e['cashAccountId'])}', widget.farmId), body: {
          'name': _name.text.trim(),
          'accountType': _type,
          'allowNegative': _allowNegative,
          'isActive': _isActive,
          'defaultFor': defaultFor,
          'notes': notes,
        });
        if (mounted) trackerToast(context, 'Account updated', description: _name.text.trim());
      } else {
        await widget.api.post(rFin('/accounts', widget.farmId), body: {
          'name': _name.text.trim(),
          'accountType': _type,
          'openingBalance': ?opening,
          'allowNegative': _allowNegative,
          'defaultFor': defaultFor,
          'notes': notes,
          'farmId': widget.farmId,
        });
        if (mounted) trackerToast(context, 'Account created', description: _name.text.trim());
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not save account', description: e.message, error: true);
    }
  }

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) => InkWell(
        onTap: () => onChanged(!value),
        child: Row(children: [
          Checkbox(value: value, onChanged: (v) => onChanged(v == true)),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        ]),
      );

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: rDialog(
          title: _e != null ? 'Edit account' : 'New account',
          description: _e != null ? tStr(_e['name']) : 'Add a place where the restaurant keeps money.',
          children: [
            rField('Name', AppInput(controller: _name, hintText: 'e.g. Front till'), required: true),
            rField(
              'Type',
              AppSelect<String>(
                value: _type,
                items: [for (final t in restaurantAccountTypes) AppSelectItem(value: t, label: _typeLabel(t))],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
            ),
            if (_e == null) rField('Opening balance', rNumberInput(_opening, hint: '0.00', signed: true)),
            if (_type == 'Till')
              const Text('Tills are cash drawers used in shifts — open and close them on the Tills page.',
                  style: TextStyle(fontSize: 12, color: TColors.slate500)),
            rField(
              'Default for',
              AppSelect<String>(
                value: _defaultFor,
                items: [
                  const AppSelectItem(value: _none, label: 'None'),
                  for (final d in ['Cash', 'Bank', 'MobileMoney']) AppSelectItem(value: d, label: _defaultForLabel(d)),
                ],
                onChanged: (v) => setState(() => _defaultFor = v ?? _none),
              ),
            ),
            _check('Allow negative balance', _allowNegative, (v) => setState(() => _allowNegative = v)),
            if (_e != null) _check('Active', _isActive, (v) => setState(() => _isActive = v)),
            rField('Notes', AppInput(controller: _notes, hintText: 'Optional')),
          ],
          actions: [
            rCancel(context, 'Cancel', busy: _saving),
            rConfirm(_saving ? 'Saving...' : (_e != null ? 'Save changes' : 'Create account'), _saving ? null : _save),
          ],
        ),
      );
}

// ------------------------------------------------------------------ Ledger

class _LedgerDialog extends StatefulWidget {
  const _LedgerDialog({required this.api, required this.farmId, required this.account, required this.gh});
  final ApiClient api;
  final String farmId;
  final Map account;
  final FarmMoney gh;

  @override
  State<_LedgerDialog> createState() => _LedgerDialogState();
}

class _LedgerDialogState extends State<_LedgerDialog> {
  String _from = _firstOfMonth();
  String _to = rTodayIso();
  List<Map> _rows = [];
  bool _loading = false;
  int _page = 1, _pageSize = 25;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await widget.api.get(rFin('/accounts/${tIntOrNull(widget.account['cashAccountId'])}/ledger', widget.farmId, {'from': _from, 'to': _to}));
      if (mounted) {
        setState(() {
          _rows = rowsOf(r);
          _page = 1;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        trackerToast(context, 'Could not load ledger', description: e.message, error: true);
        setState(() => _rows = []);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final gh = widget.gh;
    return rDialog(
      title: 'Ledger — ${tStr(widget.account['name'])}',
      description: 'Current balance ${gh(tNum(widget.account['currentBalance']))}. Newest first.',
      children: [
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.end, children: [
          SizedBox(width: 160, child: rField('From', rDateInput(_from, (v) => setState(() => _from = v)))),
          SizedBox(width: 160, child: rField('To', rDateInput(_to, (v) => setState(() => _to = v)))),
          OutlinedButton(onPressed: _loading ? null : _load, child: Text(_loading ? 'Loading...' : 'Load')),
        ]),
        if (_loading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('Loading...', style: TextStyle(color: TColors.slate500))))
        else if (_rows.isEmpty)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No entries in this period.', style: TextStyle(color: TColors.slate500))))
        else ...[
          TrackerTable(
            columns: const [
              TCol('Date', width: 95),
              TCol('What', width: 150),
              TCol('Description', width: 200),
              TCol('Amount', right: true, width: 110),
              TCol('Balance', right: true, width: 110),
            ],
            rows: [
              for (final r in pageSlice(_rows, _page, _pageSize))
                () {
                  final a = tNum(r['amount']);
                  final bal = tNum(r['runningBalance']);
                  return [
                    cellText(tStr(r['txnDate']).length >= 10 ? tStr(r['txnDate']).substring(0, 10) : tStr(r['txnDate']), color: TColors.slate500),
                    cellText(ledgerSourceLabel(r['sourceType'])),
                    cellText(tStr(r['description']).isEmpty ? '—' : tStr(r['description']), color: TColors.slate600),
                    cellText('${a >= 0 ? '+' : '−'}${gh(a.abs())}', color: a >= 0 ? const Color(0xFF16A34A) : TColors.red600, bold: true),
                    cellText(gh(bal), color: bal < 0 ? TColors.red600 : null),
                  ];
                }(),
            ],
          ),
          CompactPager(
            total: _rows.length,
            page: _page,
            pageSize: _pageSize,
            onPage: (p) => setState(() => _page = p),
            onPageSize: (v) => setState(() {
              _pageSize = v;
              _page = 1;
            }),
          ),
        ],
      ],
      actions: [OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

// ------------------------------------------------------------------ Count

class _CountDialog extends StatefulWidget {
  const _CountDialog({required this.api, required this.farmId, required this.account, required this.gh});
  final ApiClient api;
  final String farmId;
  final Map account;
  final FarmMoney gh;

  @override
  State<_CountDialog> createState() => _CountDialogState();
}

class _CountDialogState extends State<_CountDialog> {
  final _counted = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;

  num get _system => tNum(widget.account['currentBalance']);
  num? get _value => _counted.text.trim().isEmpty ? null : num.tryParse(_counted.text.trim());

  @override
  void dispose() {
    _counted.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final v = _value;
    if (v == null) {
      trackerToast(context, 'Enter the counted balance', description: 'Type the amount you counted or confirmed.', error: true);
      return;
    }
    setState(() => _saving = true);
    final name = tStr(widget.account['name']);
    try {
      await widget.api.post(rFin('/counts', widget.farmId), body: {
        'cashAccountId': tIntOrNull(widget.account['cashAccountId']),
        'counted': v,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (!mounted) return;
      final diff = v - _system;
      trackerToast(context, 'Count posted',
          description: diff == 0 ? '$name balances exactly.' : '$name is ${widget.gh(diff.abs())} ${diff > 0 ? 'over' : 'short'}.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not post count', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _value;
    final diff = v == null ? null : v - _system;
    return PopScope(
      canPop: !_saving,
      child: rDialog(
        title: 'Count — ${tStr(widget.account['name'])}',
        description: 'Count the cash (or check the statement) and enter what is really there. Any difference is posted to the ledger.',
        children: [
          rFigureBox('System balance', widget.gh(_system)),
          rField('Counted / confirmed balance', rNumberInput(_counted, onChanged: () => setState(() {}), signed: true), required: true),
          if (diff != null)
            Text(
              diff == 0 ? 'Balances exactly.' : '${widget.gh(diff.abs())} ${diff > 0 ? 'over' : 'short'}',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: diff > 0 ? const Color(0xFF16A34A) : diff < 0 ? TColors.red600 : TColors.slate700),
            ),
          rField('Notes', AppInput(controller: _notes, hintText: 'Optional')),
        ],
        actions: [
          rCancel(context, 'Cancel', busy: _saving),
          rConfirm(_saving ? 'Posting...' : 'Post count', _saving || v == null ? null : _post, color: restaurantRose),
        ],
      ),
    );
  }
}
