import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/form_dialog.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../../shared/iam_permissions.dart';
import '../../shared/reason_dialog.dart' show companyToday;
import '../../shared/reason_select.dart';
import '../money/money_widgets.dart';
import '../poultry_links.dart';
import '../reports/report_format.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';
import 'balances_logic.dart' show pageSlice;
import 'balances_widgets.dart';
import 'credit_widgets.dart';
import 'sale_reversal.dart' show showRefundCredit;
import 'sales_logic.dart' show refundMethods;

/// Poultry → Sales → Customer Credits, as `app/customer-credits/page.tsx`
/// (migrations 351, 363, 367): money the business received and still holds for
/// a customer, with no active sale to apply it to. Credit held per customer
/// (opening into each credit event), credit added by hand, and refunds.
/// Everything is derived on the server; using credit is done from the sale.

const _viewKey = 'poultry.customer-balances.view';
const _refundKey = 'poultry.customer-payments.create';

const manualCreditKindLabel = {
  'OpeningCredit': 'Opening balance',
  'Deposit': 'Customer advance',
  'CreditNote': 'Credit note',
};

/// KIND_TONE: (fg, border).
(Color, Color) _kindTone(Object? k) => switch (k) {
      'Deposit' => (TColors.emerald700, TColors.emerald300),
      'CreditNote' => (TColors.amber700, TColors.amber300),
      _ => (TColors.slate700, TColors.slate300),
    };

class CustomerCreditsScreen extends StatefulWidget {
  const CustomerCreditsScreen({super.key, required this.session, required this.company, this.initialTab, this.initialSearch});
  final Session session;
  final Company company;

  /// The web's deep link from Customer Payments: `?tab=manual&q=<payment number>`
  /// opens the hand-added credit that cannot be reversed there.
  final String? initialTab;
  final String? initialSearch;
  @override
  State<CustomerCreditsScreen> createState() => _CustomerCreditsScreenState();
}

class _CustomerCreditsScreenState extends State<CustomerCreditsScreen> {
  static const _base = '/api/Poultry/customer-payments';
  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  String _tab = 'held';
  List<Map> _rows = [], _refunds = [], _manual = [];
  bool _loading = true;
  String? _error;
  final _search = TextEditingController();
  bool _permsLoaded = false;
  Set<String> _held = {};
  FarmMoney _money = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;
  final _page = {'held': 1, 'manual': 1, 'refunds': 1};
  final _size = {'held': 10, 'manual': 10, 'refunds': 10};

  bool get _canView => !_permsLoaded || _held.contains(_viewKey);
  bool get _canRefund => _held.contains(_refundKey);

  /// usePermissions().isAdmin: anyone who is not plain staff. Adding or
  /// reversing credit by hand, and reversing a refund, are theirs alone.
  bool get _canManage => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    if (const {'held', 'manual', 'refunds'}.contains(widget.initialTab)) _tab = widget.initialTab!;
    if ((widget.initialSearch ?? '').isNotEmpty) _search.text = widget.initialSearch!;
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    canDoAll(widget.session, widget.company, const [_viewKey, _refundKey]).then((h) {
      if (!mounted) return;
      setState(() {
        _held = h;
        _permsLoaded = true;
      });
      if (_canView) _load();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Future.wait([
        _api.get('$_base/credit', query: {'farmId': _farmId}),
        _api.get('$_base/refunds', query: {'farmId': _farmId}),
        // An API without 363 has no such list: the tab is simply empty.
        _api.get('$_base/credit/manual', query: {'farmId': _farmId}).catchError((Object _) => <Map>[]),
      ]);
      if (mounted) {
        setState(() {
          _rows = rowsOf(r[0]);
          _refunds = rowsOf(r[1]);
          _manual = rowsOf(r[2]);
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isEmpty ? 'Could not load customer credit.' : e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<List<Map>> _events(int customerId) async =>
      rowsOf(await _api.get('$_base/credit/events', query: {'farmId': _farmId, 'customerId': '$customerId'}));

  String _q() => _search.text.trim().toLowerCase();
  bool _has(Object? v, String q) => tStr(v).toLowerCase().contains(q);

  List<Map> get _heldRows {
    final q = _q();
    return [for (final r in _rows) if (q.isEmpty || _has(r['customerName'], q)) r];
  }

  List<Map> get _manualRows {
    final q = _q();
    return [for (final r in _manual) if (q.isEmpty || _has(r['customerName'], q) || _has(r['paymentNumber'], q)) r];
  }

  List<Map> get _refundRows {
    final q = _q();
    return [for (final r in _refunds) if (q.isEmpty || _has(r['customerName'], q) || _has(r['refundNumber'], q)) r];
  }

  String _dt(Object? d, [Map? row]) => fmtDateTime(d, row, _offset);
  String _customer(Map r) => tStr(r['customerName']).isEmpty ? 'Customer ${tStr(r['customerId'])}' : tStr(r['customerName']);
  String _kindLabel(Object? k) => manualCreditKindLabel[tStr(k)] ?? tStr(k);

  // ------------------------------------------------------------------ actions

  Future<void> _refund({required int customerId, required String customerName, required num available, int? paymentId, String? label}) async {
    final ok = await showRefundCredit(
      context,
      session: widget.session,
      company: widget.company,
      customerId: customerId,
      customerName: customerName,
      availableCredit: available,
      poultryPaymentId: paymentId,
      creditLabel: label,
    );
    if (!ok || !mounted) return;
    trackerToast(context, 'Refund recorded', description: 'Paid back to $customerName. It shows in Cash Flow as a customer refund.');
    _load();
  }

  Future<void> _reverseManual(Map m) async {
    final name = tStr(m['customerName']).isEmpty ? 'The customer' : tStr(m['customerName']);
    final kind = _kindLabel(m['kind']).toLowerCase();
    final ok = await showReverseWithReason(
      context,
      title: 'Reverse ${tStr(m['paymentNumber']).isEmpty ? 'credit' : tStr(m['paymentNumber'])}?',
      description: 'The credit stays in the history, marked Reversed. $name no longer holds it.',
      action: 'Reverse credit · ${_money(tNum(m['amount']))}',
      bodyTitle: 'What happens',
      body: [
        bullet('${_money(tNum(m['amount']))} $kind is cancelled.'),
        if (tNum(m['used']) > 0) bullet('${_money(tNum(m['used']))} of it was used on sales. Those sales will be owed again.', color: TColors.amber800),
        if (tNum(m['refunded']) > 0)
          bullet('${_money(tNum(m['refunded']))} of it was refunded. Reverse that refund first (Refunds tab).', color: TColors.amber800),
        if (m['kind'] == 'Deposit')
          bullet(
              '${tStr(m['cashAccountName']).isEmpty ? 'Its cash account' : tStr(m['cashAccountName'])} goes down by ${_money(tNum(m['amount']))}, shown in Cash Flow as a payment reversal.'),
        if (m['kind'] == 'CreditNote') bullet('It comes off Profit & Loss.'),
      ],
      onConfirm: (reason) => _api.post(
        '$_base/credit/manual/${Uri.encodeComponent(tStr(m['paymentGroupId']))}/reverse?farmId=${Uri.encodeQueryComponent(_farmId)}',
        body: {'farmId': _farmId, 'reason': reason},
      ),
    );
    if (!ok || !mounted) return;
    trackerToast(context, 'Credit reversed',
        description:
            '${tStr(m['paymentNumber']).isEmpty ? 'The credit' : tStr(m['paymentNumber'])} for ${tStr(m['customerName']).isEmpty ? 'the customer' : tStr(m['customerName'])} was reversed.');
    _load();
  }

  Future<void> _reverseRefund(Map r) async {
    final amount = _money(tNum(r['amount']));
    final account = tStr(r['accountName']);
    final ok = await showReverseWithReason(
      context,
      title: 'Reverse refund ${tStr(r['refundNumber'])}?',
      description: 'The refund stays in the history, marked Reversed.',
      action: 'Reverse refund · $amount',
      body: [
        warnBox([
          const TextSpan(text: 'Reversing this refund will restore '),
          TextSpan(text: amount, style: boldSpan),
          TextSpan(text: " to ${tStr(r['customerName']).isEmpty ? 'the customer' : tStr(r['customerName'])}'s credit and add "),
          TextSpan(text: amount, style: boldSpan),
          const TextSpan(text: ' back to '),
          TextSpan(text: account.isEmpty ? 'the account it was paid from' : account, style: boldSpan),
          const TextSpan(text: '. Only continue if the refund was entered by mistake, or the refunded money has come back to the business.'),
        ]),
        const SizedBox(height: 10),
        const Text("Cash Flow keeps the refund's money out and shows the reversal as money in today.",
            style: TextStyle(fontSize: 13, color: TColors.slate600)),
      ],
      onConfirm: (reason) => _api.post(
        '$_base/refunds/${tStr(r['refundId'])}/reverse?farmId=${Uri.encodeQueryComponent(_farmId)}',
        body: {'farmId': _farmId, 'reason': reason},
      ),
    );
    if (!ok || !mounted) return;
    trackerToast(context, 'Refund reversed',
        description:
            "${tStr(r['refundNumber'])}: $amount is back in ${account.isEmpty ? 'the account' : account} and back on ${tStr(r['customerName']).isEmpty ? 'the customer' : tStr(r['customerName'])}'s credit.");
    _load();
  }

  Future<void> _addCredit() async {
    final c = await showDialog<Map>(
      context: context,
      builder: (_) => _ManualCreditDialog(session: widget.session, company: widget.company, money: _money),
    );
    if (c == null || !mounted) return;
    final number = tStr(c['paymentNumber']);
    trackerToast(context, 'Credit added',
        description:
            '${_money(tNum(c['amount']))} ${_kindLabel(c['kind']).toLowerCase()} for ${tStr(c['customerName'])}${number.isEmpty ? '' : ' ($number)'}.');
    setState(() => _tab = 'manual');
    _load();
  }

  /// A credit added by hand is reversed through its manual-credit document.
  Map? _manualFor(Map e) {
    if (e['isManual'] != true) return null;
    for (final m in _manual) {
      if (tStr(m['paymentGroupId']) == tStr(e['paymentGroupId']) && m['status'] != 'Reversed') return m;
    }
    return null;
  }

  Future<void> _openEvents(Map r) => showCreditEvents(
        context,
        title: "${tStr(r['customerName'])}'s credits",
        icon: Icons.savings_outlined,
        iconColor: TColors.blue600,
        load: () => _events(tIntOrNull(r['customerId']) ?? 0),
        heading: (e) => '${tStr(e['paymentNumber']).isEmpty ? '#${tStr(e['poultryPaymentId'])}' : tStr(e['paymentNumber'])} · ${tStr(e['source'])}',
        subline: (e) => '${_dt(e['creditDate'])}${tStr(e['reference']).isNotEmpty ? ' · ${tStr(e['reference'])}' : ''}',
        money: (n) => _money(n),
        actions: (e, close) {
          final m = _canManage ? _manualFor(e) : null;
          return [
            if (_canRefund && tNum(e['available']) > 0)
              cardAction('Refund', Icons.payments_outlined, () {
                close();
                _refund(
                  customerId: tIntOrNull(e['customerId']) ?? 0,
                  customerName: tStr(e['customerName']),
                  available: tNum(e['available']),
                  paymentId: tIntOrNull(e['poultryPaymentId']),
                  label: [e['paymentNumber'], e['source']].map(tStr).where((s) => s.isNotEmpty).join(' · '),
                );
              }),
            if (m != null)
              cardAction('Reverse', Icons.undo, () {
                close();
                _reverseManual(m);
              }),
          ];
        },
      );

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/customer-credits');
    final appBar = AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Customer Credits'));
    if (!_canView) {
      return Scaffold(
        appBar: appBar,
        body: ListView(padding: const EdgeInsets.all(14), children: const [
          TCard(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('You do not have access to customer credits.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
            ),
          ),
        ]),
      );
    }
    final totalHeld = _rows.fold<num>(0, (t, r) => t + tNum(r['availableCredit']));
    final totalOwed = _rows.fold<num>(0, (t, r) => t + tNum(r['outstanding']));
    final totalRefunded = _refunds.where((r) => r['status'] != 'Reversed').fold<num>(0, (t, r) => t + tNum(r['amount']));
    return Scaffold(
      appBar: appBar,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.savings_outlined, size: 22, color: TColors.blue600),
              SizedBox(width: 8),
              Expanded(child: Text('Customer Credits', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Money held for customers that is not on any active sale: kept when a sale was reversed, paid in advance, '
              'the part of a payment not used on a sale, or added by hand. Use it on their next sale (tick "Use '
              'customer credit" when adding the sale), or refund it. Open a customer to see each credit.',
              style: TextStyle(fontSize: 13, color: TColors.slate600),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (_canManage)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: TColors.blue600),
                  onPressed: _addCredit,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add credit'),
                ),
              OutlinedButton.icon(
                onPressed: () => openPoultryHref(context, widget.session, widget.company, '/customer-balances', label: 'Customer Balances'),
                icon: const Icon(Icons.people_outline, size: 16),
                label: const Text('Customer Balances'),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : _load,
                icon: _loading
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ]),
            const SizedBox(height: 14),
            twoUp([
              creditKpi('Available credit', _money(totalHeld), color: creditBlue700),
              creditKpi('Customers with credit', '${_rows.length}'),
              creditKpi('They still owe (not netted)', _money(totalOwed), color: TColors.amber700),
              creditKpi('Refunded', _money(totalRefunded)),
            ]),
            if (_error != null) ...[const SizedBox(height: 12), TrackerBanner.error(_error!)],
            const SizedBox(height: 14),
            CreditTabs(
              value: _tab,
              onChanged: (v) => setState(() => _tab = v),
              tabs: [
                ('held', Icons.savings_outlined, 'Available credit', _rows.length),
                ('manual', Icons.edit_outlined, 'Added by hand', _manual.length),
                ('refunds', Icons.payments_outlined, 'Refunds', _refunds.length),
              ],
            ),
            const SizedBox(height: 10),
            AppInput(
              controller: _search,
              hintText: 'Search customer',
              prefixIcon: const Icon(Icons.search, size: 18),
              onChanged: (_) => setState(() => _page.updateAll((_, _) => 1)),
            ),
            const SizedBox(height: 12),
            ...switch (_tab) {
              'manual' => _manualTab(),
              'refunds' => _refundsTab(),
              _ => _heldTab(),
            },
          ],
        ),
      ),
    );
  }

  CompactPager _pager(String tab, int total) => CompactPager(
        total: total,
        page: _page[tab]!,
        pageSize: _size[tab]!,
        onPage: (p) => setState(() => _page[tab] = p),
        onPageSize: (s) => setState(() {
          _size[tab] = s;
          _page[tab] = 1;
        }),
      );

  Widget _empty(String text) => TCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
        ),
      );

  List<Widget> _heldTab() {
    final rows = _heldRows;
    final q = _q();
    return [
      if (_loading && _rows.isEmpty)
        const TCard(child: LoadingLine('Loading…'))
      else if (rows.isEmpty)
        _empty(q.isNotEmpty ? 'No customer matches.' : 'No customer has credit. Nothing is being held for anyone.')
      else
        MobileCardList<Map>(
          items: pageSlice(rows, _page['held']!, _size['held']!),
          keyOf: (r) => tStr(r['customerId']),
          primary: (r) => tStr(r['customerName']),
          secondary: (r) {
            final n = tIntOrNull(r['paymentCount']) ?? 0;
            return '$n credit${n == 1 ? '' : 's'}';
          },
          highlights: (r) => [
            Highlight('Available', _money(tNum(r['availableCredit'])), accent: Accent.blue),
            Highlight('Owes', _money(tNum(r['outstanding'])), accent: tNum(r['outstanding']) > 0 ? Accent.amber : Accent.slate),
          ],
          actions: (r) => [
            cardAction('Credits', Icons.savings_outlined, () => _openEvents(r)),
            if (_canRefund)
              cardAction(
                'Refund',
                Icons.payments_outlined,
                () => _refund(
                  customerId: tIntOrNull(r['customerId']) ?? 0,
                  customerName: tStr(r['customerName']),
                  available: tNum(r['availableCredit']),
                ),
              ),
          ],
          table: (items) => TrackerTable(
            columns: const [
              TCol('Customer', width: 180),
              TCol('Available credit', right: true, width: 130),
              TCol('Credits', right: true, width: 80),
              TCol('Still owes', right: true, width: 120),
              TCol('Actions', right: true, width: 210),
            ],
            rows: [
              for (final r in items)
                [
                  InkWell(
                    onTap: () => _openEvents(r),
                    child: Text(tStr(r['customerName']), style: const TextStyle(fontWeight: FontWeight.w500)),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(_money(tNum(r['availableCredit'])), style: const TextStyle(fontWeight: FontWeight.w600, color: creditBlue700)),
                  ),
                  Align(alignment: Alignment.centerRight, child: Text(tStr(r['paymentCount']))),
                  Align(alignment: Alignment.centerRight, child: Text(_money(tNum(r['outstanding'])))),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(onPressed: () => _openEvents(r), child: const Text('Credits')),
                    if (_canRefund)
                      TextButton(
                        onPressed: () => _refund(
                          customerId: tIntOrNull(r['customerId']) ?? 0,
                          customerName: tStr(r['customerName']),
                          available: tNum(r['availableCredit']),
                        ),
                        child: const Text('Refund'),
                      ),
                  ]),
                ],
            ],
          ),
          pager: _pager('held', rows.length),
        ),
      const SizedBox(height: 8),
      const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.shopping_cart_outlined, size: 14, color: TColors.slate500)),
        SizedBox(width: 6),
        Expanded(
          child: Text(
            'To use credit, add the customer\'s next sale on the Sales page and tick "Use customer credit", or use the Pay dialog on a sale they owe. No new money is recorded.',
            style: TextStyle(fontSize: 12, color: TColors.slate500),
          ),
        ),
      ]),
    ];
  }

  List<Widget> _manualTab() {
    final rows = _manualRows;
    final emptyText = 'No credit has been added by hand.${_canManage ? ' Use Add credit for an opening balance, a customer advance or a credit note.' : ''}';
    if (rows.isEmpty) return [_empty(emptyText)];
    return [
      MobileCardList<Map>(
        items: pageSlice(rows, _page['manual']!, _size['manual']!),
        keyOf: (r) => tStr(r['paymentGroupId']),
        primary: _customer,
        secondary: (r) => '${_kindLabel(r['kind'])} · ${tStr(r['paymentNumber'])} · ${_dt(r['creditDate'], r)}',
        trailing: (r) => r['status'] == 'Reversed' ? greyBadge('Reversed') : null,
        highlights: (r) => [
          Highlight('Amount', _money(tNum(r['amount'])), accent: Accent.blue),
          Highlight('Left', _money(tNum(r['remaining']))),
        ],
        details: (r) => [
          ('Used on sales', _money(tNum(r['used']))),
          ('Refunded', _money(tNum(r['refunded']))),
          (
            'Cash',
            r['kind'] == 'Deposit'
                ? ([r['cashAccountName'], r['paymentMethod']].map(tStr).where((s) => s.isNotEmpty).join(' · ').ifEmpty('—'))
                : 'None'
          ),
          (
            'Reason',
            r['status'] == 'Reversed'
                ? '${tStr(r['reason'])} (reversed: ${tStr(r['reversalReason'])})'
                : tStr(r['reason']).ifEmpty('—')
          ),
        ],
        actions: (r) => [
          if (_canManage && r['status'] != 'Reversed') cardAction('Reverse', Icons.undo, () => _reverseManual(r)),
        ],
        table: (items) => TrackerTable(
          columns: const [
            TCol('Number', width: 110),
            TCol('Date', width: 140),
            TCol('Customer', width: 160),
            TCol('Kind', width: 150),
            TCol('Amount', right: true, width: 110),
            TCol('Used', right: true, width: 110),
            TCol('Left', right: true, width: 110),
            TCol('Reason', width: 220),
            TCol('Actions', right: true, width: 120),
          ],
          rows: [
            for (final r in items)
              () {
                final reversed = r['status'] == 'Reversed';
                final (fg, border) = _kindTone(r['kind']);
                return <Widget>[
                  cellText(tStr(r['paymentNumber']).ifEmpty('—'), bold: true, strike: reversed, color: reversed ? TColors.slate400 : null),
                  cellText(_dt(r['creditDate'], r), color: reversed ? TColors.slate400 : null),
                  cellText(_customer(r), color: reversed ? TColors.slate400 : null),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TBadge(_kindLabel(r['kind']), bg: Colors.white, fg: fg, border: border),
                    if (r['kind'] == 'Deposit' && tStr(r['cashAccountName']).isNotEmpty)
                      Text([r['cashAccountName'], r['paymentMethod']].map(tStr).where((s) => s.isNotEmpty).join(' · '),
                          style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                  ]),
                  Align(alignment: Alignment.centerRight, child: cellText(_money(tNum(r['amount'])), strike: reversed)),
                  Align(alignment: Alignment.centerRight, child: cellText(_money(tNum(r['used']) + tNum(r['refunded'])))),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(reversed ? '—' : _money(tNum(r['remaining'])), style: const TextStyle(fontWeight: FontWeight.w600, color: creditBlue700)),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tStr(r['reason']), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (reversed)
                      Text('Reversed: ${tStr(r['reversalReason'])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                  ]),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _canManage && !reversed
                        ? TextButton(onPressed: () => _reverseManual(r), child: const Text('Reverse'))
                        : reversed
                            ? greyBadge('Reversed')
                            : const SizedBox.shrink(),
                  ),
                ];
              }(),
          ],
        ),
        pager: _pager('manual', rows.length),
      ),
    ];
  }

  List<Widget> _refundsTab() {
    final rows = _refundRows;
    if (rows.isEmpty) return [_empty('No refunds yet.')];
    return [
      MobileCardList<Map>(
        items: pageSlice(rows, _page['refunds']!, _size['refunds']!),
        keyOf: (r) => tStr(r['refundId']),
        primary: _customer,
        secondary: (r) => '${tStr(r['refundNumber'])} · ${_dt(r['refundDate'], r)}',
        trailing: (r) => r['status'] == 'Reversed' ? greyBadge('Reversed') : null,
        highlights: (r) => [Highlight('Refunded', _money(tNum(r['amount'])), accent: Accent.rose)],
        details: (r) => [
          ('From', tStr(r['accountName']).ifEmpty('—')),
          ('Method', tStr(r['paymentMethod']).ifEmpty('—')),
          ('Credit', tStr(r['paymentNumbers']).ifEmpty('—')),
          ('Reason', tStr(r['reason']).ifEmpty('—')),
          if (r['status'] == 'Reversed')
            ('Reversed', '${tStr(r['reversalDate']).isNotEmpty ? _dt(r['reversalDate']) : ''} ${tStr(r['reversalReason'])}'.trim().ifEmpty('—')),
        ],
        actions: (r) => [
          if (_canManage && r['status'] == 'Posted') cardAction('Reverse refund', Icons.undo, () => _reverseRefund(r)),
        ],
        table: (items) => TrackerTable(
          columns: const [
            TCol('Refund', width: 110),
            TCol('Date', width: 140),
            TCol('Customer', width: 160),
            TCol('Amount', right: true, width: 110),
            TCol('Paid from', width: 170),
            TCol('Credit', width: 130),
            TCol('Reason', width: 240),
            TCol('Status', width: 100),
            TCol('Actions', right: true, width: 110),
          ],
          rows: [
            for (final r in items)
              () {
                final reversed = r['status'] == 'Reversed';
                final grey = reversed ? TColors.slate400 : null;
                return <Widget>[
                  cellText(tStr(r['refundNumber']), bold: true, strike: reversed, color: grey),
                  cellText(_dt(r['refundDate'], r), color: grey),
                  cellText(_customer(r), color: grey),
                  Align(alignment: Alignment.centerRight, child: cellText(_money(tNum(r['amount'])), strike: reversed, color: grey)),
                  cellText([r['accountName'], r['paymentMethod']].map(tStr).where((s) => s.isNotEmpty).join(' · ').ifEmpty('—'), color: grey),
                  cellText(tStr(r['paymentNumbers']).ifEmpty('—'), color: grey),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tStr(r['reason']), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (reversed)
                      Text(
                        'Reversed${tStr(r['reversalDate']).isNotEmpty ? ' ${_dt(r['reversalDate'])}' : ''}: ${tStr(r['reversalReason'])}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                  ]),
                  reversed ? greyBadge(tStr(r['status'])) : TBadge(tStr(r['status']), bg: Colors.white, fg: TColors.slate700, border: TColors.slate300),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _canManage && !reversed ? TextButton(onPressed: () => _reverseRefund(r), child: const Text('Reverse')) : const SizedBox.shrink(),
                  ),
                ];
              }(),
          ],
        ),
        pager: _pager('refunds', rows.length),
      ),
    ];
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

// =============================================================================
// Add customer credit (components/sales/manual-credit-dialog.tsx), owner/admin.
// =============================================================================

const _kinds = [
  (
    'OpeningCredit',
    'Opening balance',
    'Credit the customer already had before you started using the system. No cash moves and profit is not affected.',
  ),
  (
    'Deposit',
    'Customer advance',
    'The customer paid in advance, before buying anything. The money goes into the cash account you choose and shows in Cash Flow.',
  ),
  (
    'CreditNote',
    'Credit note',
    'Credit you give the customer, e.g. for broken eggs or a late delivery. No cash moves; it is a cost, shown on Profit & Loss.',
  ),
];

class _ManualCreditDialog extends StatefulWidget {
  const _ManualCreditDialog({required this.session, required this.company, required this.money});
  final Session session;
  final Company company;
  final FarmMoney money;
  @override
  State<_ManualCreditDialog> createState() => _ManualCreditDialogState();
}

class _ManualCreditDialogState extends State<_ManualCreditDialog> {
  List<(int, String)> _customers = [];
  bool _customersLoaded = false;
  List<Map> _accounts = [];
  int? _customer;
  String _kind = 'OpeningCredit';
  final _amount = TextEditingController();
  String _date = localToday();
  int? _account;
  String _method = 'Cash';
  final _reference = TextEditingController();
  String _reason = '';
  bool _saving = false;
  String? _error;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    companyToday(widget.session, widget.company).then((t) {
      if (mounted && t.isNotEmpty) setState(() => _date = t);
    });
    _api.get('/api/Customer', query: {'userId': widget.session.tokens.userId ?? '', 'farmId': _farmId}).then((res) {
      final list = <(int, String)>[
        for (final c in rowsOf(res))
          if ((tIntOrNull(c['customerId'] ?? c['id']) ?? 0) > 0 && tStr(c['name'] ?? c['customerName']).isNotEmpty)
            (tIntOrNull(c['customerId'] ?? c['id'])!, tStr(c['name'] ?? c['customerName'])),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      if (mounted) setState(() => _customers = list);
    }).catchError((Object _) {}).whenComplete(() {
      if (mounted) setState(() => _customersLoaded = true);
    });
    _api.get('/api/Poultry/cash-accounts', query: {'farmId': _farmId}).then((res) {
      final active = [for (final a in rowsOf(res)) if (a['isActive'] != false) a];
      if (mounted) {
        setState(() {
          _accounts = active;
          _account = tIntOrNull(active.firstOrNull?['poultryCashAccountId']);
        });
      }
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  num get _value => ((num.tryParse(_amount.text) ?? 0) * 100).round() / 100;
  bool get _isDeposit => _kind == 'Deposit';
  bool get _valid => _customer != null && _value > 0 && _reason.trim().isNotEmpty && _date.isNotEmpty && (!_isDeposit || _account != null);
  String get _customerName => _customers.where((c) => c.$1 == _customer).firstOrNull?.$2 ?? '';

  Future<void> _save() async {
    if (!_valid) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await _api.post('/api/Poultry/customer-payments/credit/manual?farmId=${Uri.encodeQueryComponent(_farmId)}', body: {
        'customerId': _customer,
        'kind': _kind,
        'amount': _value,
        'creditDate': _date,
        'poultryCashAccountId': _isDeposit ? _account : null,
        'paymentMethod': _isDeposit ? _method : null,
        'reference': _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        'reason': _reason.trim(),
        'farmId': _farmId,
      });
      if (mounted) {
        Navigator.pop(context, {
          'customerName': _customerName,
          'kind': _kind,
          'amount': _value,
          'paymentNumber': res is Map ? res['paymentNumber'] : null,
        });
      }
      return;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final accountName = tStr(_accounts.where((a) => tIntOrNull(a['poultryCashAccountId']) == _account).firstOrNull?['accountName']);
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const FormDialogTitle(icon: Icons.savings_outlined, color: FormColor.blue, text: 'Add customer credit'),
        content: SizedBox(
          width: 672,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Money held for a customer, to use on their next sales or refund. Say where it came from — that decides whether cash or profit moves.',
                style: TextStyle(fontSize: 13, color: TColors.slate500),
              ),
              const SizedBox(height: 16),
              TintedSection(title: 'Customer & Date', color: FormColor.blue, children: [
                FormPair(
                  stackOnMobile: true,
                  FilterLabel(
                    'Customer *',
                    AppSelect<int>(
                      value: _customer,
                      hintText: _customers.isNotEmpty || _customersLoaded ? 'Choose the customer' : 'Loading customers…',
                      items: [for (final (id, name) in _customers) AppSelectItem(value: id, label: name)],
                      onChanged: (v) => setState(() => _customer = v),
                    ),
                  ),
                  FilterLabel(
                    _kind == 'OpeningCredit' ? 'As at *' : 'Date *',
                    FilterDate(value: _date, hint: 'Date', onChanged: (v) => setState(() => _date = v)),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              TintedSection(title: 'Where the credit came from *', color: FormColor.amber, gap: 0, children: [
                for (final (value, title, body) in _kinds)
                  kindOption(
                    selected: _kind == value,
                    title: title,
                    body: body,
                    onTap: () => setState(() {
                      _kind = value;
                      _reason = '';
                    }),
                  ),
              ]),
              const SizedBox(height: 16),
              TintedSection(title: 'Amount', color: FormColor.green, children: [
                FormPair(
                  FilterLabel(
                    'Amount *',
                    AppInput(
                      controller: _amount,
                      hintText: '0.00',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  FilterLabel(
                    'Reference',
                    AppInput(controller: _reference, hintText: 'Optional, e.g. receipt'),
                  ),
                ),
                if (_isDeposit)
                  FormPair(
                    FilterLabel(
                      'Received into *',
                      AppSelect<int>(
                        value: _account,
                        hintText: 'Cash account',
                        items: [
                          for (final a in _accounts) AppSelectItem(value: tIntOrNull(a['poultryCashAccountId'])!, label: tStr(a['accountName'])),
                        ],
                        onChanged: (v) => setState(() => _account = v),
                      ),
                    ),
                    FilterLabel(
                      'Method',
                      AppSelect<String>(
                        value: _method,
                        items: [for (final m in refundMethods) AppSelectItem(value: m, label: m)],
                        onChanged: (v) => setState(() => _method = v ?? _method),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 16),
              TintedSection(title: 'Reason', color: FormColor.slate, children: [
                ReasonSelect(
                  key: ValueKey(_kind),
                  options: customerCreditReasons[_kind]!,
                  value: _reason,
                  onChanged: (v) => setState(() => _reason = v),
                ),
              ]),
              if (_value > 0 && _customerName.isNotEmpty) ...[
                const SizedBox(height: 12),
                summaryBox(tone: FormColor.blue, [
                  TextSpan(text: '$_customerName will hold '),
                  TextSpan(text: widget.money(_value), style: boldSpan),
                  const TextSpan(text: ' of credit. '),
                  TextSpan(
                    text: _isDeposit
                        ? '${accountName.isEmpty ? 'The account' : accountName} goes up by the same amount.'
                        : _kind == 'CreditNote'
                            ? 'Profit & Loss shows it as a credit note (a cost). No cash moves.'
                            : 'No cash moves and profit is not affected.',
                  ),
                ]),
              ],
              if (_error != null) ...[const SizedBox(height: 10), TrackerBanner.error(_error!)],
            ],
          ),
        ),
        actions: [
          FormDialogFooter(onCancel: () => Navigator.pop(context), cancelDisabled: _saving, children: [
            FilledButton(
              style: formPrimary(FormColor.blue),
              onPressed: !_valid || _saving ? null : _save,
              child: Text(_saving ? 'Adding…' : _value > 0 ? 'Add credit · ${widget.money(_value)}' : 'Add credit'),
            ),
          ]),
        ],
      ),
    );
  }
}
