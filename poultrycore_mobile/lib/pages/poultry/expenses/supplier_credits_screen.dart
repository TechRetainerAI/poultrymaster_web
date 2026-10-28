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
import '../sales/balances_logic.dart' show pageSlice, entryTimestamp;
import '../sales/balances_widgets.dart';
import '../sales/credit_widgets.dart';
import '../sales/sales_logic.dart' show refundMethods;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';

/// Poultry → Expenses → Supplier Credits, as `app/supplier-credits/page.tsx`
/// with `components/suppliers/supplier-credit-dialogs.tsx` (migration 370):
/// money a supplier holds for the business — an advance paid before delivery,
/// the part of a payment not applied, or a credit added by hand. Applying it to
/// a purchase moves no cash; a supplier refund is real Money In.

const _viewKey = 'poultry.supplier-balances.view';
const _payKey = 'poultry.supplier-payments.create';

const supplierCreditKindLabel = {
  'SupplierCreditNote': 'Credit note',
  'SupplierOpeningCredit': 'Opening credit',
  'SupplierManualCredit': 'Manual credit',
};

/// Credits added by hand cannot be refunded in cash.
const _noRefundSources = ['SupplierCreditNote', 'SupplierOpeningCredit', 'SupplierManualCredit'];

String _join(List<Object?> parts) => parts.map(tStr).where((s) => s.isNotEmpty).join(' · ');
String _or(String s, String other) => s.isEmpty ? other : s;

class SupplierCreditsScreen extends StatefulWidget {
  const SupplierCreditsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<SupplierCreditsScreen> createState() => _SupplierCreditsScreenState();
}

class _SupplierCreditsScreenState extends State<SupplierCreditsScreen> {
  static const _base = '/api/Poultry/supplier-credits';
  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  String get _fq => 'farmId=${Uri.encodeQueryComponent(_farmId)}';

  String _tab = 'held';
  List<Map> _rows = [], _apps = [], _refunds = [];
  bool _loading = true;
  String? _error;
  final _search = TextEditingController();
  bool _permsLoaded = false;
  Set<String> _held = {};
  FarmMoney _money = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;
  final _page = {'held': 1, 'applied': 1, 'refunds': 1};
  final _size = {'held': 10, 'applied': 10, 'refunds': 10};

  bool get _canView => !_permsLoaded || _held.contains(_viewKey);

  /// Paying an advance, applying credit and taking a refund.
  bool get _canPay => _held.contains(_payKey);

  /// usePermissions().isAdmin: anyone who is not plain staff. Added by hand,
  /// and every reversal or unapply.
  bool get _canManage => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    canDoAll(widget.session, widget.company, const [_viewKey, _payKey]).then((h) {
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
        _api.get(_base, query: {'farmId': _farmId}),
        _api.get('$_base/applications', query: {'farmId': _farmId}),
        _api.get('$_base/refunds', query: {'farmId': _farmId}),
      ]);
      if (mounted) {
        setState(() {
          _rows = rowsOf(r[0]);
          _apps = rowsOf(r[1]);
          _refunds = rowsOf(r[2]);
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isEmpty ? 'Could not load supplier credit.' : e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<List<Map>> _events(int supplierId) async =>
      rowsOf(await _api.get('$_base/events', query: {'farmId': _farmId, 'supplierId': '$supplierId'}));

  String _q() => _search.text.trim().toLowerCase();
  bool _has(Object? v, String q) => tStr(v).toLowerCase().contains(q);
  String _dt(Object? d) => fmtDateTime(d, null, _offset);
  String _supplier(Map r) => _or(tStr(r['supplierName']), 'Supplier ${tStr(r['supplierId'])}');
  String _appliedTo(Map r) => _or(tStr(r['reference']), '${tStr(r['documentType'])} #${tStr(r['documentId'])}');

  List<Map> get _heldRows {
    final q = _q();
    return [for (final r in _rows) if (q.isEmpty || _has(r['supplierName'], q)) r];
  }

  List<Map> get _appRows {
    final q = _q();
    return [for (final r in _apps) if (q.isEmpty || _has(r['supplierName'], q) || _has(r['reference'], q)) r];
  }

  List<Map> get _refundRows {
    final q = _q();
    return [for (final r in _refunds) if (q.isEmpty || _has(r['supplierName'], q) || _has(r['refundNumber'], q)) r];
  }

  // ------------------------------------------------------------------ actions

  Future<void> _payAdvance() async {
    final a = await showDialog<Map>(
      context: context,
      builder: (_) => _PayAdvanceDialog(session: widget.session, company: widget.company, money: _money),
    );
    if (a == null || !mounted) return;
    trackerToast(context, 'Advance paid',
        description: '${_money(tNum(a['amount']))} to ${tStr(a['supplierName'])}, held as their credit. It shows in Cash Flow as money out.');
    setState(() => _tab = 'held');
    _load();
  }

  Future<void> _addCredit() async {
    final c = await showDialog<Map>(
      context: context,
      builder: (_) => _SupplierCreditDialog(session: widget.session, company: widget.company, money: _money),
    );
    if (c == null || !mounted) return;
    trackerToast(context, 'Credit added',
        description:
            '${_money(tNum(c['amount']))} ${(supplierCreditKindLabel[c['kind']] ?? '').toLowerCase()} from ${tStr(c['supplierName'])}. No cash moved.');
    setState(() => _tab = 'held');
    _load();
  }

  Future<void> _apply(Map e) async {
    final a = await showDialog<Map>(
      context: context,
      builder: (_) => _ApplyCreditDialog(session: widget.session, company: widget.company, money: _money, credit: e),
    );
    if (a == null || !mounted) return;
    trackerToast(context, 'Credit applied', description: '${_money(tNum(a['amount']))} paid on ${tStr(a['reference'])}. No money moved.');
    _load();
  }

  Future<void> _refund(Map e) async {
    final r = await showDialog<num>(
      context: context,
      builder: (_) => _SupplierRefundDialog(session: widget.session, company: widget.company, money: _money, credit: e),
    );
    if (r == null || !mounted) return;
    trackerToast(context, 'Refund recorded', description: '${_money(r)} came back from the supplier. It shows in Cash Flow as money in.');
    _load();
  }

  Future<void> _reverseCredit(Map e) async {
    final ok = await showReverseWithReason(
      context,
      title: 'Reverse ${tStr(e['creditNumber'])}?',
      description: 'It stays in the history, marked as reversed.',
      action: 'Reverse',
      body: [
        warnBox(tIntOrNull(e['poultryCashAccountId']) != null
            ? [
                const TextSpan(text: 'The advance of '),
                TextSpan(text: _money(tNum(e['originalAmount'])), style: boldSpan),
                const TextSpan(text: ' is cancelled and '),
                TextSpan(text: _or(tStr(e['accountName']), 'its account'), style: boldSpan),
                const TextSpan(text: ' goes back up by the same amount. Only continue if it was entered by mistake.'),
              ]
            : [
                TextSpan(text: 'The ${tStr(e['source']).toLowerCase()} of '),
                TextSpan(text: _money(tNum(e['originalAmount'])), style: boldSpan),
                const TextSpan(text: ' is cancelled. No cash moves.'),
              ]),
      ],
      onConfirm: (reason) => _api.post('$_base/${tStr(e['poultrySupplierPaymentId'])}/reverse?$_fq', body: {'reason': reason, 'farmId': _farmId}),
    );
    if (!ok || !mounted) return;
    trackerToast(context, 'Credit reversed', description: '${tStr(e['creditNumber'])} for ${_or(tStr(e['supplierName']), 'the supplier')} was reversed.');
    _load();
  }

  Future<void> _unapply(Map a) async {
    final ok = await showReverseWithReason(
      context,
      title: 'Unapply this credit?',
      description: 'It stays in the history, marked as reversed.',
      action: 'Unapply',
      body: [
        warnBox([
          TextSpan(text: _money(tNum(a['amount'])), style: boldSpan),
          TextSpan(text: ' goes back on ${tStr(a['creditNumber'])}, and ${_or(tStr(a['reference']), 'the item')} is owed again. No cash moves.'),
        ]),
      ],
      onConfirm: (reason) =>
          _api.post('$_base/applications/${tStr(a['allocationId'])}/reverse?$_fq', body: {'reason': reason, 'farmId': _farmId}),
    );
    if (!ok || !mounted) return;
    trackerToast(context, 'Credit unapplied',
        description: '${_money(tNum(a['amount']))} is back on ${tStr(a['creditNumber'])}; ${_or(tStr(a['reference']), 'the item')} is owed again.');
    _load();
  }

  Future<void> _reverseRefund(Map r) async {
    final account = _or(tStr(r['accountName']), 'the account');
    final ok = await showReverseWithReason(
      context,
      title: 'Reverse refund ${tStr(r['refundNumber'])}?',
      description: 'It stays in the history, marked as reversed.',
      action: 'Reverse',
      body: [
        warnBox([
          const TextSpan(text: 'The credit gets '),
          TextSpan(text: _money(tNum(r['amount'])), style: boldSpan),
          const TextSpan(text: ' back and '),
          TextSpan(text: account, style: boldSpan),
          const TextSpan(
              text: ' goes down by the same amount. Only continue if the refund was entered by mistake or the money was returned to the supplier.'),
        ]),
      ],
      onConfirm: (reason) => _api.post('$_base/refunds/${tStr(r['refundId'])}/reverse?$_fq', body: {'reason': reason, 'farmId': _farmId}),
    );
    if (!ok || !mounted) return;
    trackerToast(context, 'Refund reversed',
        description: '${tStr(r['refundNumber'])}: the credit is back and $account goes down by ${_money(tNum(r['amount']))}.');
    _load();
  }

  Future<void> _openEvents(Map r) => showCreditEvents(
        context,
        title: "${tStr(r['supplierName'])}'s credits",
        icon: Icons.account_balance_wallet_outlined,
        iconColor: TColors.amber600,
        color: FormColor.amber,
        load: () => _events(tIntOrNull(r['supplierId']) ?? 0),
        heading: (e) => '${tStr(e['creditNumber'])} · ${tStr(e['source'])}',
        subline: (e) => '${_dt(e['creditDate'])}${tStr(e['reference']).isNotEmpty ? ' · ${tStr(e['reference'])}' : ''}',
        money: (n) => _money(n),
        actions: (e, close) {
          final available = tNum(e['available']);
          final source = tStr(e['sourceType']);
          return [
            if (_canPay && available > 0)
              cardAction('Apply', Icons.link, () {
                close();
                _apply(e);
              }),
            if (_canPay && available > 0 && source.isNotEmpty && !_noRefundSources.contains(source))
              cardAction('Refund', Icons.download_outlined, () {
                close();
                _refund(e);
              }),
            if (_canManage && e['isManual'] == true && tNum(e['applied']) == 0 && tNum(e['refunded']) == 0)
              cardAction('Reverse', Icons.undo, () {
                close();
                _reverseCredit(e);
              }),
          ];
        },
      );

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/supplier-credits');
    final appBar = AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Supplier Credits'));
    if (!_canView) {
      return Scaffold(
        appBar: appBar,
        body: ListView(padding: const EdgeInsets.all(14), children: const [
          TCard(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('You do not have access to supplier credits.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
            ),
          ),
        ]),
      );
    }
    final totalHeld = _rows.fold<num>(0, (t, r) => t + tNum(r['availableCredit']));
    final totalOwed = _rows.fold<num>(0, (t, r) => t + tNum(r['owed']));
    final totalReturned = _refunds.where((r) => r['status'] == 'Posted').fold<num>(0, (t, r) => t + tNum(r['amount']));
    return Scaffold(
      appBar: appBar,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.account_balance_wallet_outlined, size: 22, color: TColors.amber600),
              SizedBox(width: 8),
              Expanded(
                child: Text('Supplier Credits & Advances', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900)),
              ),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Money a supplier holds for you: advances paid before delivery, the part of a payment not used on a purchase, '
              'and credit notes. Apply it to their purchases (no money moves), or record money they send back. '
              'Open a supplier to see each credit.',
              style: TextStyle(fontSize: 13, color: TColors.slate600),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (_canPay)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: TColors.amber600),
                  onPressed: _payAdvance,
                  icon: const Icon(Icons.account_balance_wallet_outlined, size: 16),
                  label: const Text('Pay advance'),
                ),
              if (_canManage)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: TColors.blue600),
                  onPressed: _addCredit,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add credit'),
                ),
              OutlinedButton.icon(
                onPressed: () => openPoultryHref(context, widget.session, widget.company, '/supplier-balances', label: 'Supplier Balances'),
                icon: const Icon(Icons.local_shipping_outlined, size: 16),
                label: const Text('Supplier Balances'),
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
              creditKpi('Available credit with suppliers', _money(totalHeld), color: creditBlue700),
              creditKpi('Suppliers with credit', '${_rows.length}'),
              creditKpi('You still owe them (not netted)', _money(totalOwed), color: TColors.amber700),
              creditKpi('Sent back by suppliers', _money(totalReturned)),
            ]),
            if (_error != null) ...[const SizedBox(height: 12), TrackerBanner.error(_error!)],
            const SizedBox(height: 14),
            CreditTabs(
              value: _tab,
              onChanged: (v) => setState(() => _tab = v),
              tabs: [
                ('held', Icons.account_balance_wallet_outlined, 'Available credit', _rows.length),
                ('applied', Icons.link, 'Applied', _apps.length),
                ('refunds', Icons.download_outlined, 'Refunds', _refunds.length),
              ],
            ),
            const SizedBox(height: 10),
            AppInput(
              controller: _search,
              hintText: 'Search supplier',
              prefixIcon: const Icon(Icons.search, size: 18),
              onChanged: (_) => setState(() => _page.updateAll((_, _) => 1)),
            ),
            const SizedBox(height: 12),
            ...switch (_tab) {
              'applied' => _appliedTab(),
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
    if (_loading && _rows.isEmpty) return const [TCard(child: LoadingLine('Loading…'))];
    if (rows.isEmpty) return [_empty(_q().isNotEmpty ? 'No supplier matches.' : 'No supplier holds credit for you.')];
    return [
      MobileCardList<Map>(
        items: pageSlice(rows, _page['held']!, _size['held']!),
        keyOf: (r) => tStr(r['supplierId']),
        primary: (r) => tStr(r['supplierName']),
        secondary: (r) {
          final n = tIntOrNull(r['creditCount']) ?? 0;
          return '$n credit${n == 1 ? '' : 's'}';
        },
        highlights: (r) => [
          Highlight('Available', _money(tNum(r['availableCredit'])), accent: Accent.blue),
          Highlight('You owe', _money(tNum(r['owed'])), accent: tNum(r['owed']) > 0 ? Accent.amber : Accent.slate),
        ],
        actions: (r) => [cardAction('Credits', Icons.account_balance_wallet_outlined, () => _openEvents(r))],
        table: (items) => TrackerTable(
          columns: const [
            TCol('Supplier', width: 180),
            TCol('Available credit', right: true, width: 130),
            TCol('Credits', right: true, width: 80),
            TCol('You still owe', right: true, width: 120),
          ],
          rows: [
            for (final r in items)
              [
                InkWell(
                  onTap: () => _openEvents(r),
                  child: Text(tStr(r['supplierName']), style: const TextStyle(fontWeight: FontWeight.w500)),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(_money(tNum(r['availableCredit'])), style: const TextStyle(fontWeight: FontWeight.w600, color: creditBlue700)),
                ),
                Align(alignment: Alignment.centerRight, child: Text(tStr(r['creditCount']))),
                Align(alignment: Alignment.centerRight, child: Text(_money(tNum(r['owed'])))),
              ],
          ],
        ),
        pager: _pager('held', rows.length),
      ),
    ];
  }

  List<Widget> _appliedTab() {
    final rows = _appRows;
    if (rows.isEmpty) return [_empty('No supplier credit has been applied yet.')];
    return [
      MobileCardList<Map>(
        items: pageSlice(rows, _page['applied']!, _size['applied']!),
        keyOf: (r) => tStr(r['allocationId']),
        primary: _supplier,
        secondary: (r) => '${tStr(r['creditNumber'])} → ${_appliedTo(r)} · ${_dt(r['appliedDate'])}',
        trailing: (r) => r['status'] == 'Reversed' ? greyBadge('Undone') : null,
        highlights: (r) => [Highlight('Applied', _money(tNum(r['amount'])), accent: Accent.blue)],
        details: (r) => [
          ('On', _or(tStr(r['label']), '—')),
          if (r['status'] == 'Reversed') ('Undone', _or(tStr(r['reversalReason']), '—')),
        ],
        actions: (r) => [
          if (_canManage && r['status'] == 'Posted') cardAction('Unapply', Icons.undo, () => _unapply(r)),
        ],
        table: (items) => TrackerTable(
          columns: const [
            TCol('Date', width: 140),
            TCol('Supplier', width: 160),
            TCol('Credit', width: 110),
            TCol('Applied to', width: 200),
            TCol('Amount', right: true, width: 110),
            TCol('Status', width: 100),
            TCol('Actions', right: true, width: 110),
          ],
          rows: [
            for (final r in items)
              () {
                final undone = r['status'] == 'Reversed';
                final grey = undone ? TColors.slate400 : null;
                return <Widget>[
                  cellText(_dt(r['appliedDate']), color: grey),
                  cellText(_supplier(r), color: grey),
                  cellText(tStr(r['creditNumber']), bold: true, color: grey),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    cellText(_appliedTo(r), color: grey),
                    if (tStr(r['label']).isNotEmpty) Text(tStr(r['label']), style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                    if (undone && tStr(r['reversalReason']).isNotEmpty)
                      Text('Undone: ${tStr(r['reversalReason'])}', style: const TextStyle(fontSize: 11)),
                  ]),
                  Align(alignment: Alignment.centerRight, child: cellText(_money(tNum(r['amount'])), strike: undone, color: grey)),
                  undone ? greyBadge('Undone') : const TBadge('Applied', bg: Colors.white, fg: TColors.slate700, border: TColors.slate300),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _canManage && !undone ? TextButton(onPressed: () => _unapply(r), child: const Text('Unapply')) : const SizedBox.shrink(),
                  ),
                ];
              }(),
          ],
        ),
        pager: _pager('applied', rows.length),
      ),
    ];
  }

  List<Widget> _refundsTab() {
    final rows = _refundRows;
    if (rows.isEmpty) return [_empty('No supplier has sent money back.')];
    return [
      MobileCardList<Map>(
        items: pageSlice(rows, _page['refunds']!, _size['refunds']!),
        keyOf: (r) => tStr(r['refundId']),
        primary: _supplier,
        secondary: (r) => '${tStr(r['refundNumber'])} · ${_dt(r['refundDate'])}',
        trailing: (r) => r['status'] == 'Reversed' ? greyBadge('Reversed') : null,
        highlights: (r) => [Highlight('Received', _money(tNum(r['amount'])), accent: Accent.emerald)],
        details: (r) => [
          ('Into', _or(tStr(r['accountName']), '—')),
          ('Credit', _or(tStr(r['creditNumbers']), '—')),
          ('Reason', _or(tStr(r['reason']), '—')),
        ],
        actions: (r) => [
          if (_canManage && r['status'] == 'Posted') cardAction('Reverse refund', Icons.undo, () => _reverseRefund(r)),
        ],
        table: (items) => TrackerTable(
          columns: const [
            TCol('Refund', width: 110),
            TCol('Date', width: 140),
            TCol('Supplier', width: 160),
            TCol('Amount', right: true, width: 110),
            TCol('Received into', width: 170),
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
                  cellText(_dt(r['refundDate']), color: grey),
                  cellText(_supplier(r), color: grey),
                  Align(alignment: Alignment.centerRight, child: cellText(_money(tNum(r['amount'])), strike: reversed, color: grey)),
                  cellText(_or(_join([r['accountName'], r['paymentMethod']]), '—'), color: grey),
                  cellText(_or(tStr(r['creditNumbers']), '—'), color: grey),
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

// =============================================================================
// The four dialogs of components/suppliers/supplier-credit-dialogs.tsx
// =============================================================================

Future<List<(int, String)>> _loadSuppliers(Session session, Company company) async {
  try {
    final res = await session.farmClient.get('/api/Supplier', query: {'userId': session.tokens.userId ?? '', 'farmId': company.farmId});
    return [
      for (final s in rowsOf(res))
        if ((tIntOrNull(s['supplierId']) ?? 0) > 0 && tStr(s['name']).isNotEmpty) (tIntOrNull(s['supplierId'])!, tStr(s['name'])),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
  } on ApiException {
    return [];
  }
}

Future<List<Map>> _loadAccounts(Session session, Company company) async {
  try {
    final res = await session.farmClient.get('/api/Poultry/cash-accounts', query: {'farmId': company.farmId});
    return [for (final a in rowsOf(res)) if (a['isActive'] != false) a];
  } on ApiException {
    return [];
  }
}

Widget _numInput(TextEditingController c, VoidCallback onChanged, {bool enabled = true}) => AppInput(
      controller: c,
      hintText: '0.00',
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
      onChanged: (_) => onChanged(),
    );

Widget _dialogTitle(IconData icon, FormColor color, String text) => FormDialogTitle(icon: icon, color: color, text: text);

Widget _blurb(String text) => Text(text, style: const TextStyle(fontSize: 13, color: TColors.slate500));

/// "Available on this credit": a box in the dialog's colour (blue to apply,
/// emerald to refund).
Widget _available(String money, {FormColor tone = FormColor.blue}) => summaryBox(tone: tone, [
      const TextSpan(text: 'Available on this credit: '),
      TextSpan(text: money, style: const TextStyle(fontWeight: FontWeight.w600)),
    ]);

/// The footer: red-outline Cancel and the main button, which carries the
/// amount once there is one ("Pay advance · GH₵ 50.00").
List<Widget> _dialogActions(BuildContext context,
        {required bool saving, required bool valid, required String label, required FormColor color, required VoidCallback onSave, String? amount}) {
  final text = amount == null ? label : '$label · $amount';
  return [
    FormDialogFooter(onCancel: () => Navigator.pop(context), cancelDisabled: saving, children: [
      FilledButton(
        style: formPrimary(color),
        onPressed: !valid || saving ? null : onSave,
        child: !saving
            ? Text(text)
            : Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                const SizedBox(width: 8),
                Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
              ]),
      ),
    ]),
  ];
}

String _accountLabel(Map a, FarmMoney money) => '${tStr(a['accountName'])} · ${money(tNum(a['currentBalance']))}';

// ------------------------------------------------------------------ advance

class _PayAdvanceDialog extends StatefulWidget {
  const _PayAdvanceDialog({required this.session, required this.company, required this.money});
  final Session session;
  final Company company;
  final FarmMoney money;
  @override
  State<_PayAdvanceDialog> createState() => _PayAdvanceDialogState();
}

class _PayAdvanceDialogState extends State<_PayAdvanceDialog> {
  List<(int, String)> _suppliers = [];
  bool _suppliersLoaded = false;
  List<Map> _accounts = [];
  int? _supplier, _account;
  final _amount = TextEditingController(), _reference = TextEditingController(), _notes = TextEditingController();
  String _date = localToday();
  String _method = 'Cash';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    companyToday(widget.session, widget.company).then((t) {
      if (mounted && t.isNotEmpty) setState(() => _date = t);
    });
    _loadSuppliers(widget.session, widget.company).then((l) {
      if (mounted) {
        setState(() {
          _suppliers = l;
          _suppliersLoaded = true;
        });
      }
    });
    _loadAccounts(widget.session, widget.company).then((l) {
      if (mounted) {
        setState(() {
          _accounts = l;
          _account ??= tIntOrNull(l.firstOrNull?['poultryCashAccountId']);
        });
      }
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  num get _value => ((num.tryParse(_amount.text) ?? 0) * 100).round() / 100;
  bool get _valid => _supplier != null && _value > 0 && _account != null && _date.isNotEmpty;
  String get _supplierName => _suppliers.where((s) => s.$1 == _supplier).firstOrNull?.$2 ?? '';

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.session.farmClient.post('/api/Poultry/supplier-payments', body: {
        'partyId': _supplier,
        'amount': _value,
        'paymentDate': entryTimestamp(_date),
        'paymentMethod': _method,
        'cashAccountId': _account,
        'reference': _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'sourceType': 'SupplierCredits',
        // Applied to nothing: the whole amount is the supplier's credit.
        'allocations': <Map>[],
        'farmId': widget.company.farmId,
        'createdBy': widget.session.tokens.userId,
      });
      if (mounted) Navigator.pop(context, {'supplierName': _supplierName, 'amount': _value});
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
        title: _dialogTitle(Icons.account_balance_wallet_outlined, FormColor.amber, 'Pay supplier advance'),
        content: SizedBox(
          width: 672,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _blurb('Pay a supplier before anything is delivered. The money leaves the account you choose and is held as their '
                  'credit, to use on their next purchases. It is not a purchase and not an expense.'),
              const SizedBox(height: 16),
              TintedSection(title: 'Supplier & Date', color: FormColor.blue, children: [
                FormPair(
                  stackOnMobile: true,
                  FilterLabel(
                    'Supplier *',
                    AppSelect<int>(
                      value: _supplier,
                      hintText: _suppliers.isNotEmpty || _suppliersLoaded ? 'Choose the supplier' : 'Loading suppliers…',
                      items: [for (final (id, name) in _suppliers) AppSelectItem(value: id, label: name)],
                      onChanged: (v) => setState(() => _supplier = v),
                    ),
                  ),
                  FilterLabel('Date *', FilterDate(value: _date, hint: 'Date', onChanged: (v) => setState(() => _date = v))),
                ),
              ]),
              const SizedBox(height: 16),
              TintedSection(title: 'Payment', color: FormColor.green, children: [
                FormPair(
                  FilterLabel('Amount *', _numInput(_amount, () => setState(() {}))),
                  FilterLabel(
                    'Pay from *',
                    AppSelect<int>(
                      value: _account,
                      hintText: 'Cash account',
                      items: [
                        for (final a in _accounts) AppSelectItem(value: tIntOrNull(a['poultryCashAccountId'])!, label: _accountLabel(a, widget.money)),
                      ],
                      onChanged: (v) => setState(() => _account = v),
                    ),
                  ),
                ),
                FormPair(
                  FilterLabel(
                    'Method *',
                    AppSelect<String>(
                      value: _method,
                      items: [for (final m in refundMethods) AppSelectItem(value: m, label: m)],
                      onChanged: (v) => setState(() => _method = v ?? _method),
                    ),
                  ),
                  FilterLabel('Reference', AppInput(controller: _reference, hintText: 'Optional, e.g. receipt or transfer ID')),
                ),
              ]),
              const SizedBox(height: 16),
              TintedSection(title: 'Notes', color: FormColor.slate, children: [
                AppInput(controller: _notes, minLines: 2, maxLines: 4, hintText: 'Optional, e.g. maize for next month'),
              ]),
              if (_value > 0 && _supplierName.isNotEmpty) ...[
                const SizedBox(height: 12),
                summaryBox(tone: FormColor.amber, [
                  TextSpan(text: '${_or(accountName, 'The account')} goes down by '),
                  TextSpan(text: widget.money(_value), style: boldSpan),
                  TextSpan(text: ', and $_supplierName holds the same amount as credit for you.'),
                ]),
              ],
              if (_error != null) ...[const SizedBox(height: 10), TrackerBanner.error(_error!)],
            ],
          ),
        ),
        actions: _dialogActions(context,
            saving: _saving, valid: _valid, label: 'Pay advance', color: FormColor.amber, onSave: _save,
            amount: _value > 0 ? widget.money(_value) : null),
      ),
    );
  }
}

// ------------------------------------------------------------ manual credit

const _supplierKinds = [
  ('SupplierCreditNote', 'The supplier issued a credit note, e.g. for a short or damaged delivery.'),
  ('SupplierOpeningCredit', 'Credit the supplier already held for you before you started using the system.'),
  ('SupplierManualCredit', 'Any other credit the supplier owes you, recorded by hand.'),
];

class _SupplierCreditDialog extends StatefulWidget {
  const _SupplierCreditDialog({required this.session, required this.company, required this.money});
  final Session session;
  final Company company;
  final FarmMoney money;
  @override
  State<_SupplierCreditDialog> createState() => _SupplierCreditDialogState();
}

class _SupplierCreditDialogState extends State<_SupplierCreditDialog> {
  List<(int, String)> _suppliers = [];
  bool _suppliersLoaded = false;
  int? _supplier;
  String _kind = 'SupplierCreditNote';
  final _amount = TextEditingController(), _reference = TextEditingController();
  String _date = localToday();
  String _reason = '';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    companyToday(widget.session, widget.company).then((t) {
      if (mounted && t.isNotEmpty) setState(() => _date = t);
    });
    _loadSuppliers(widget.session, widget.company).then((l) {
      if (mounted) {
        setState(() {
          _suppliers = l;
          _suppliersLoaded = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  num get _value => ((num.tryParse(_amount.text) ?? 0) * 100).round() / 100;
  bool get _valid => _supplier != null && _value > 0 && _reason.trim().isNotEmpty && _date.isNotEmpty;
  String get _supplierName => _suppliers.where((s) => s.$1 == _supplier).firstOrNull?.$2 ?? '';

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final farmId = widget.company.farmId;
    try {
      await widget.session.farmClient.post('/api/Poultry/supplier-credits/manual?farmId=${Uri.encodeQueryComponent(farmId)}', body: {
        'supplierId': _supplier,
        'kind': _kind,
        'amount': _value,
        'creditDate': _date,
        'reference': _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        'reason': _reason.trim(),
        'farmId': farmId,
      });
      if (mounted) Navigator.pop(context, {'supplierName': _supplierName, 'amount': _value, 'kind': _kind});
      return;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: AlertDialog(
          scrollable: true,
          title: _dialogTitle(Icons.note_alt_outlined, FormColor.blue, 'Add supplier credit'),
          content: SizedBox(
            width: 672,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _blurb('Credit a supplier owes you with no money moving now. If you paid them money in advance, use Pay advance instead.'),
                const SizedBox(height: 16),
                TintedSection(title: 'Supplier & Date', color: FormColor.blue, children: [
                  FormPair(
                    stackOnMobile: true,
                    FilterLabel(
                      'Supplier *',
                      AppSelect<int>(
                        value: _supplier,
                        hintText: _suppliers.isNotEmpty || _suppliersLoaded ? 'Choose the supplier' : 'Loading suppliers…',
                        items: [for (final (id, name) in _suppliers) AppSelectItem(value: id, label: name)],
                        onChanged: (v) => setState(() => _supplier = v),
                      ),
                    ),
                    FilterLabel('Date *', FilterDate(value: _date, hint: 'Date', onChanged: (v) => setState(() => _date = v))),
                  ),
                ]),
                const SizedBox(height: 16),
                TintedSection(title: 'What is it *', color: FormColor.amber, gap: 0, children: [
                  for (final (value, body) in _supplierKinds)
                    kindOption(
                      selected: _kind == value,
                      title: supplierCreditKindLabel[value]!,
                      body: body,
                      onTap: () => setState(() => _kind = value),
                    ),
                ]),
                const SizedBox(height: 16),
                TintedSection(title: 'Amount', color: FormColor.green, children: [
                  FormPair(
                    FilterLabel('Amount *', _numInput(_amount, () => setState(() {}))),
                    FilterLabel('Reference', AppInput(controller: _reference, hintText: 'Optional, e.g. credit note number')),
                  ),
                ]),
                const SizedBox(height: 16),
                TintedSection(title: 'Reason *', color: FormColor.slate, children: [
                  ReasonSelect(options: supplierCreditReasons, value: _reason, onChanged: (v) => setState(() => _reason = v)),
                ]),
                if (_value > 0 && _supplierName.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  summaryBox(tone: FormColor.blue, [
                    TextSpan(text: '$_supplierName will hold '),
                    TextSpan(text: widget.money(_value), style: boldSpan),
                    const TextSpan(text: ' of credit for you. No cash moves.'),
                  ]),
                ],
                if (_error != null) ...[const SizedBox(height: 10), TrackerBanner.error(_error!)],
              ],
            ),
          ),
          actions: _dialogActions(context,
              saving: _saving, valid: _valid, label: 'Add credit', color: FormColor.blue, onSave: _save,
              amount: _value > 0 ? widget.money(_value) : null),
        ),
      );
}

// ---------------------------------------------------------------- apply

class _ApplyCreditDialog extends StatefulWidget {
  const _ApplyCreditDialog({required this.session, required this.company, required this.money, required this.credit});
  final Session session;
  final Company company;
  final FarmMoney money;
  final Map credit;
  @override
  State<_ApplyCreditDialog> createState() => _ApplyCreditDialogState();
}

class _ApplyCreditDialogState extends State<_ApplyCreditDialog> {
  List<Map>? _docs;
  String? _docKey;
  final _amount = TextEditingController();
  bool _saving = false;
  String? _error;

  Map get c => widget.credit;
  num get _creditAvailable => tNum(c['available']);
  String _key(Map d) => '${tStr(d['documentType'])}:${tStr(d['documentId'])}';
  Map? get _doc => _docs?.where((d) => _key(d) == _docKey).firstOrNull;

  @override
  void initState() {
    super.initState();
    widget.session.farmClient
        .get('/api/Poultry/supplier-balances/${tStr(c['supplierId'])}/open-purchases', query: {'farmId': widget.company.farmId})
        .then((res) {
      if (mounted) setState(() => _docs = rowsOf(res));
    }).catchError((Object _) {
      if (mounted) setState(() => _docs = []);
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  num get _value => ((num.tryParse(_amount.text) ?? 0) * 100).round() / 100;
  num get _max {
    final d = _doc;
    if (d == null) return 0;
    final b = tNum(d['balance']);
    return b < _creditAvailable ? b : _creditAvailable;
  }

  bool get _valid => _doc != null && _value > 0 && _value <= _max + 0.005;

  Future<void> _save() async {
    final d = _doc;
    if (d == null || !_valid || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final farmId = widget.company.farmId;
    try {
      await widget.session.farmClient.post('/api/Poultry/supplier-credits/apply?farmId=${Uri.encodeQueryComponent(farmId)}', body: {
        'poultrySupplierPaymentId': tIntOrNull(c['poultrySupplierPaymentId']),
        'documentType': d['documentType'],
        'documentId': tIntOrNull(d['documentId']),
        'amount': _value,
        'farmId': farmId,
      });
      if (mounted) {
        Navigator.pop(context, {
          'reference': _or(tStr(d['reference']), '${tStr(d['documentType'])} #${tStr(d['documentId'])}'),
          'amount': _value,
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
    final docs = _docs;
    final source = tStr(c['source']);
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: _dialogTitle(Icons.link, FormColor.blue, 'Apply supplier credit'),
        content: SizedBox(
          width: 672,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _blurb('Use ${tStr(c['creditNumber'])} (${source.toLowerCase()}) to pay something ${_or(tStr(c['supplierName']), 'the supplier')} is owed. '
                  'No money moves now -- it already left with the ${source == 'Credit note' ? 'credit note' : 'payment'}.'),
              const SizedBox(height: 16),
              _available(widget.money(_creditAvailable)),
              const SizedBox(height: 16),
              TintedSection(title: 'Apply to', color: FormColor.blue, children: [
              FilterLabel(
                'Apply to *',
                docs == null
                    ? const LoadingLine('Loading what is owed…')
                    : docs.isEmpty
                        ? Text('Nothing is owed to ${_or(tStr(c['supplierName']), 'this supplier')} right now.',
                            style: const TextStyle(fontSize: 13, color: TColors.slate500))
                        : AppSelect<String>(
                            value: _docKey,
                            hintText: 'Choose a purchase, bill or debt',
                            items: [
                              for (final d in docs)
                                AppSelectItem(
                                  value: _key(d),
                                  label:
                                      '${_or(tStr(d['reference']), tStr(d['documentId']))} · ${_or(tStr(d['label']), tStr(d['documentType']))} · owes ${widget.money(tNum(d['balance']))}',
                                ),
                            ],
                            onChanged: (v) => setState(() {
                              _docKey = v;
                              if (_doc != null) _amount.text = _max.toStringAsFixed(2);
                            }),
                          ),
              ),
              ]),
              const SizedBox(height: 16),
              TintedSection(title: 'Amount', color: FormColor.green, gap: 4, children: [
                FilterLabel('Amount *', _numInput(_amount, () => setState(() {}), enabled: _doc != null)),
                if (_doc != null) Text('At most ${widget.money(_max)}.', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
              if (_error != null) ...[const SizedBox(height: 10), TrackerBanner.error(_error!)],
            ],
          ),
        ),
        actions: _dialogActions(context,
            saving: _saving, valid: _valid, label: 'Apply credit', color: FormColor.blue, onSave: _save,
            amount: _value > 0 ? widget.money(_value) : null),
      ),
    );
  }
}

// --------------------------------------------------------------- refund

class _SupplierRefundDialog extends StatefulWidget {
  const _SupplierRefundDialog({required this.session, required this.company, required this.money, required this.credit});
  final Session session;
  final Company company;
  final FarmMoney money;
  final Map credit;
  @override
  State<_SupplierRefundDialog> createState() => _SupplierRefundDialogState();
}

class _SupplierRefundDialogState extends State<_SupplierRefundDialog> {
  List<Map> _accounts = [];
  int? _account;
  String _method = 'Cash';
  late final _amount = TextEditingController(text: tNum(widget.credit['available']).toStringAsFixed(2));
  String _date = localToday();
  String _reason = '';
  bool _saving = false;
  String? _error;

  Map get c => widget.credit;

  @override
  void initState() {
    super.initState();
    companyToday(widget.session, widget.company).then((t) {
      if (mounted && t.isNotEmpty) setState(() => _date = t);
    });
    _loadAccounts(widget.session, widget.company).then((l) {
      if (mounted) {
        setState(() {
          _accounts = l;
          _account ??= tIntOrNull(l.firstOrNull?['poultryCashAccountId']);
        });
      }
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  num get _value => ((num.tryParse(_amount.text) ?? 0) * 100).round() / 100;
  bool get _valid => _value > 0 && _value <= tNum(c['available']) + 0.005 && _account != null && _reason.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final farmId = widget.company.farmId;
    try {
      await widget.session.farmClient.post('/api/Poultry/supplier-credits/refunds?farmId=${Uri.encodeQueryComponent(farmId)}', body: {
        'poultrySupplierPaymentId': tIntOrNull(c['poultrySupplierPaymentId']),
        'amount': _value,
        'poultryCashAccountId': _account,
        'paymentMethod': _method,
        'refundDate': _date,
        'reason': _reason.trim(),
        'farmId': farmId,
      });
      if (mounted) Navigator.pop(context, _value);
      return;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: AlertDialog(
          scrollable: true,
          title: _dialogTitle(Icons.download_outlined, FormColor.emerald, 'Receive supplier refund'),
          content: SizedBox(
            width: 576,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _blurb('${_or(tStr(c['supplierName']), 'The supplier')} sends back money out of ${tStr(c['creditNumber'])}. It comes into the account you choose '
                    '(Money In on Cash Flow). It is not a sale.'),
                const SizedBox(height: 16),
                _available(widget.money(tNum(c['available'])), tone: FormColor.emerald),
                const SizedBox(height: 16),
                TintedSection(title: 'Refund', color: FormColor.green, children: [
                FormPair(
                  FilterLabel('Amount *', _numInput(_amount, () => setState(() {}))),
                  FilterLabel('Date *', FilterDate(value: _date, hint: 'Date', onChanged: (v) => setState(() => _date = v))),
                ),
                FormPair(
                  FilterLabel(
                    'Received into *',
                    AppSelect<int>(
                      value: _account,
                      hintText: 'Cash account',
                      items: [for (final a in _accounts) AppSelectItem(value: tIntOrNull(a['poultryCashAccountId'])!, label: tStr(a['accountName']))],
                      onChanged: (v) => setState(() => _account = v),
                    ),
                  ),
                  FilterLabel(
                    'Method *',
                    AppSelect<String>(
                      value: _method,
                      items: [for (final m in refundMethods) AppSelectItem(value: m, label: m)],
                      onChanged: (v) => setState(() => _method = v ?? _method),
                    ),
                  ),
                ),
                ]),
                const SizedBox(height: 16),
                TintedSection(title: 'Reason *', color: FormColor.slate, children: [
                  ReasonSelect(options: supplierRefundReasons, value: _reason, onChanged: (v) => setState(() => _reason = v)),
                ]),
                if (_error != null) ...[const SizedBox(height: 10), TrackerBanner.error(_error!)],
              ],
            ),
          ),
          actions: _dialogActions(context,
              saving: _saving, valid: _valid, label: 'Record refund', color: FormColor.emerald, onSave: _save,
              amount: _value > 0 ? widget.money(_value) : null),
        ),
      );
}
