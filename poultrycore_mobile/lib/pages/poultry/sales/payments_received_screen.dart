import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../reports/report_format.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, loc;
import '../trackers/tracker_widgets.dart';
import 'balances_logic.dart';
import 'balances_widgets.dart';
import 'sales_screen.dart';

/// Poultry → Sales, Expenses & Money → Sales → Payments, as
/// `components/payments/payments-received-page.tsx` (module "poultry"): one
/// row per payment the customer actually made, a part-paid sale folded to one
/// row carrying its payment trail, and the reversal that restores every sale a
/// payment touched. The phone layout (cards).
class PaymentsReceivedScreen extends StatefulWidget {
  const PaymentsReceivedScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<PaymentsReceivedScreen> createState() => _PaymentsReceivedScreenState();
}

class _PaymentsReceivedScreenState extends State<PaymentsReceivedScreen> {
  List<Map> _rows = [];
  bool _loading = true;
  final Map<String, List<Map>> _allocations = {};
  final Set<String> _inflight = {};
  final Map<int, List<Map>> _trails = {};
  String? _expanded;
  FarmMoney _fmt = const FarmMoney();

  final _search = TextEditingController();
  String _from = '', _to = '';
  String _method = 'all', _source = 'all', _status = 'Posted', _appliedTo = 'all';
  int _page = 1;
  int _pageSize = 10;
  int _lastTotal = -1;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  /// The web gates reversal on poultry.customer-payments.reverse; the phone
  /// has no permission flags, so Staff are the ones left out.
  bool get _canReverse => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _fmt = m);
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
      final res = await _api.get('/api/Poultry/customer-payments', query: {
        'farmId': _farmId,
        if (_from.isNotEmpty) 'from': _from,
        if (_to.isNotEmpty) 'to': _to,
      });
      if (!mounted) return;
      setState(() {
        _rows = rowsOf(res);
        // A reload drops both caches, or a reversal would keep its old detail.
        _allocations.clear();
        _trails.clear();
        _inflight.clear();
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load payments', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetchAllocation(String id) async {
    if (_allocations.containsKey(id) || !_inflight.add(id)) return;
    try {
      final res = await _api.get('/api/Poultry/customer-payments/${Uri.encodeComponent(id)}', query: {'farmId': _farmId});
      if (mounted) setState(() => _allocations.putIfAbsent(id, () => res is Map ? rowsOf(res['allocations']) : []));
    } on ApiException {
      // Silent, as the web: the row still says what it said before. It stays
      // marked, so a failing row is not asked for again until the next load.
    }
  }

  Future<void> _fetchTrail(int saleId) async {
    if (_trails.containsKey(saleId)) return;
    try {
      // No date range: the trail is the sale's whole life.
      final res = await _api.get('/api/Poultry/customer-payments', query: {'farmId': _farmId, 'saleId': '$saleId'});
      if (mounted) setState(() => _trails.putIfAbsent(saleId, () => rowsOf(res)));
    } on ApiException {
      // Silent, as the web.
    }
  }

  Future<void> _toggle(Map row) async {
    final id = tStr(row['paymentId']);
    if (_expanded == id) {
      setState(() => _expanded = null);
      return;
    }
    setState(() => _expanded = id);
    final count = tIntOrNull(row['allocationCount']) ?? 0;
    final sid = tIntOrNull(row['saleId']);
    if (count > 1) {
      await _fetchAllocation(id);
    } else if (sid != null) {
      await _fetchTrail(sid);
    }
  }

  Future<void> _reverse(Map target) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => ReversePaymentDialog(
        session: widget.session,
        company: widget.company,
        target: target,
        allocations: _allocations[tStr(target['paymentId'])],
        fmt: _fmt,
      ),
    );
    if (done == true) _load();
  }

  void _openSale(int saleId) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SalesScreen(session: widget.session, company: widget.company, focusSaleId: saleId),
      ));

  String _dateOf(Object? d) => tStr(d).isEmpty ? '—' : fmtDateTimeLike(d);

  /// The one-sale case: on the row (migration 241) or from a fetched allocation.
  ({int saleId, num? saleTotal, num? before, num? applied, num? after})? _single(Map row) {
    if (tIntOrNull(row['allocationCount']) != 1) return null;
    final sid = tIntOrNull(row['saleId']);
    if (sid != null) {
      return (
        saleId: sid,
        saleTotal: row['saleTotal'] == null ? null : tNum(row['saleTotal']),
        before: row['balanceBefore'] == null ? null : tNum(row['balanceBefore']),
        applied: tNum(row['amountApplied'] ?? row['totalAmount']),
        after: row['balanceAfter'] == null ? null : tNum(row['balanceAfter']),
      );
    }
    final a = _allocations[tStr(row['paymentId'])]?.firstOrNull;
    if (a == null) return null;
    return (
      saleId: tIntOrNull(a['documentId']) ?? 0,
      saleTotal: tNum(a['documentTotal']),
      before: tNum(a['balanceBefore']),
      applied: tNum(a['amountApplied']),
      after: tNum(a['balanceAfter']),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-payments');
    final methods = {for (final r in _rows) if (tStr(r['paymentMethod']).isNotEmpty) tStr(r['paymentMethod'])}.toList()..sort();
    final sources = {for (final r in _rows) if (tStr(r['sourceType']).isNotEmpty) tStr(r['sourceType'])}.toList()..sort();
    final filtered = filterPayments(_rows,
        search: _search.text, status: _status, method: _method, source: _source, appliedTo: _appliedTo);
    final counts = payCountBySale(_rows);
    final fold = foldPayments(filtered, counts);
    final totals = paymentTotals(filtered);
    // usePagination resets to page 1 whenever the total changes.
    if (fold.visible.length != _lastTotal) {
      _lastTotal = fold.visible.length;
      _page = 1;
    }
    final pageRows = pageSlice(fold.visible, _page, _pageSize);
    // Older APIs do not send the inline sale; fetch those rows' allocation.
    for (final r in pageRows) {
      if (tIntOrNull(r['allocationCount']) == 1 && r['saleId'] == null) _fetchAllocation(tStr(r['paymentId']));
    }

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Payments received')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.account_balance_wallet_outlined, size: 24, color: Color(0xFF0284C7)),
              SizedBox(width: 8),
              Expanded(
                child: Text('Payments received',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900)),
              ),
            ]),
            const SizedBox(height: 4),
            const Text(
              'One row per payment the customer actually made. A payment spread over several sales is one payment here — open it to see how much each sale received. A sale that was part-paid keeps one row too, with its earlier payments inside it.',
              style: TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 14),
            ListFiltersCard(
              search: _search,
              searchPlaceholder: 'Search customer, payment, method or reference',
              onSearch: () => setState(() {}),
              from: _from,
              to: _to,
              onDates: (f, t) {
                setState(() {
                  _from = f;
                  _to = t;
                });
                _load();
              },
              onClear: () {
                setState(() {
                  _search.clear();
                  _from = '';
                  _to = '';
                });
                _load();
              },
              extras: [
                FilterLabel(
                  'Method',
                  AppSelect<String>(
                    value: _method,
                    items: [const AppSelectItem(value: 'all', label: 'All methods'), for (final m in methods) AppSelectItem(value: m, label: m)],
                    onChanged: (v) => setState(() => _method = v ?? 'all'),
                  ),
                ),
                FilterLabel(
                  'Source',
                  AppSelect<String>(
                    value: _source,
                    items: [
                      const AppSelectItem(value: 'all', label: 'All sources'),
                      for (final s in sources) AppSelectItem(value: s, label: paymentsSourceLabel(s)),
                    ],
                    onChanged: (v) => setState(() => _source = v ?? 'all'),
                  ),
                ),
                FilterLabel(
                  'Applied to',
                  AppSelect<String>(
                    value: _appliedTo,
                    items: const [
                      AppSelectItem(value: 'all', label: 'Any'),
                      AppSelectItem(value: 'single', label: 'One sale'),
                      AppSelectItem(value: 'multiple', label: 'Several sales'),
                    ],
                    onChanged: (v) => setState(() => _appliedTo = v ?? 'all'),
                  ),
                ),
                FilterLabel(
                  'Status',
                  AppSelect<String>(
                    value: _status,
                    items: const [
                      AppSelectItem(value: 'Posted', label: 'Posted'),
                      AppSelectItem(value: 'Reversed', label: 'Reversed'),
                      AppSelectItem(value: 'all', label: 'All'),
                    ],
                    onChanged: (v) => setState(() => _status = v ?? 'Posted'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(builder: (context, c) {
              final w = (c.maxWidth - 10) / 2;
              Widget box(String label, String value, {Color? color, String? sub}) => SizedBox(
                    width: w,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: TColors.slate200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                        Text(value, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: color)),
                        if (sub != null) Text(sub, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                      ]),
                    ),
                  );
              return Wrap(spacing: 10, runSpacing: 10, children: [
                box('Payments', loc(totals.count), sub: fold.folded > 0 ? '${fold.folded} inside a sale’s trail' : null),
                box('Total received', _fmt(totals.amount), color: TColors.emerald700),
                box('Sales settled', loc(totals.sales)),
              ]);
            }),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: TColors.slate200),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Row(children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Loading…', style: TextStyle(color: TColors.slate500)),
                      ]),
                    )
                  : filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text(_rows.isEmpty ? 'No payments yet.' : 'No payments match those filters.',
                                style: const TextStyle(color: TColors.slate500)),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            for (var i = 0; i < pageRows.length; i++) ...[
                              _card(pageRows[i], i, counts, fold.carriers),
                              const SizedBox(height: 8),
                            ],
                            CompactPager(
                              total: fold.visible.length,
                              page: _page,
                              pageSize: _pageSize,
                              onPage: (p) => setState(() => _page = p),
                              onPageSize: (s) => setState(() {
                                _pageSize = s;
                                _page = 1;
                              }),
                            ),
                          ]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(Map row, int idx, Map<int, int> counts, Map<int, String> carriers) {
    final id = tStr(row['paymentId']);
    final reversed = isReversedPayment(row);
    final open = _expanded == id;
    final count = tIntOrNull(row['allocationCount']) ?? 0;
    final multi = count > 1;
    final sid = tIntOrNull(row['saleId']);
    final hasTrail = sid != null && carriers[sid] == id;
    final openable = multi || hasTrail;
    final times = count == 1 && sid != null && (counts[sid] ?? 0) > 1 ? counts[sid] : null;
    final one = _single(row);
    const sm = TextStyle(fontSize: 12, color: TColors.slate500);
    final stripe = idx.isEven;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: stripe ? TColors.blue100 : Colors.white,
        border: Border.all(color: stripe ? TColors.blue300 : TColors.slate200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: openable ? () => _toggle(row) : null,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(_fmt(tNum(row['totalAmount'])),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: reversed ? TColors.slate400 : TColors.slate900,
                        decoration: reversed ? TextDecoration.lineThrough : null,
                      )),
                  reversed
                      ? const TBadge('Reversed', bg: Colors.white, fg: TColors.slate500, border: TColors.slate200)
                      : const TBadge('Posted', bg: TColors.slate100, fg: TColors.slate800),
                ]),
                const SizedBox(height: 2),
                Text(tStr(row['partyName']).isEmpty ? 'Walk-in' : tStr(row['partyName']),
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: TColors.slate600)),
                const SizedBox(height: 4),
                Text('${_dateOf(row['paymentDate'])} · ${tStr(row['paymentMethod']).isEmpty ? '—' : row['paymentMethod']} · '
                    '${multi ? '$count sales' : '1 sale'}', style: sm),
              ]),
            ),
            if (openable)
              Icon(open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 18, color: TColors.slate400),
          ]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Text(paymentRef(row), style: sm, overflow: TextOverflow.ellipsis)),
          Expanded(
            child: Text('Source: ${paymentsSourceLabel(row['sourceType'])}',
                textAlign: TextAlign.right, style: sm, overflow: TextOverflow.ellipsis),
          ),
        ]),
        Row(children: [
          Expanded(
            child: Text('Ref: ${tStr(row['reference']).isEmpty ? '—' : row['reference']}', style: sm, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: Text('By: ${tStr(row['createdBy']).isEmpty ? '—' : row['createdBy']}',
                textAlign: TextAlign.right, style: sm, overflow: TextOverflow.ellipsis),
          ),
        ]),
        if (!multi && one != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xCCFFFFFF),
              border: Border.all(color: const Color(0xB3E2E8F0)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                    const Text('Sale ', style: sm),
                    InkWell(
                      onTap: () => _openSale(one.saleId),
                      child: Text('#${one.saleId}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF0369A1))),
                    ),
                    if (times != null) Text(' (paid $times times)', style: const TextStyle(fontSize: 12, color: TColors.slate400)),
                  ]),
                ),
                Text('Total ${_fmt(one.saleTotal ?? 0)}', style: sm),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: Text('Before ${_fmt(one.before ?? 0)}', style: sm)),
                Text('After ${_fmt(one.after ?? 0)}', style: sm),
              ]),
            ]),
          ),
        ],
        if (reversed && tStr(row['reversalReason']).isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
              'Reversed${tStr(row['reversedBy']).isNotEmpty ? ' by ${row['reversedBy']}' : ''}'
              '${tStr(row['reversedAt']).isNotEmpty ? ' on ${fmtDateTimeLike(row['reversedAt'])}' : ''}: ${row['reversalReason']}',
              style: sm),
        ],
        if (_canReverse && !reversed) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size.fromHeight(40)),
            onPressed: () => _reverse(row),
            icon: const Icon(Icons.undo, size: 16),
            label: const Text('Reverse'),
          ),
        ],
        if (open && !multi && sid != null) ...[
          const SizedBox(height: 8),
          _trail(sid, id),
        ],
        if (open && multi) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xCCFFFFFF),
              border: Border.all(color: const Color(0xB3E2E8F0)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: !_allocations.containsKey(id)
                ? const LoadingLine('Loading allocation…')
                : Column(children: [
                    for (final a in _allocations[id]!)
                      AllocationCard(
                        title: '#${a['documentId']}',
                        amount: _fmt(tNum(a['amountApplied'])),
                        label: tStr(a['label']),
                        date: _dateOf(a['documentDate']),
                        total: _fmt(tNum(a['documentTotal'])),
                        before: _fmt(tNum(a['balanceBefore'])),
                        after: _fmt(tNum(a['balanceAfter'])),
                      ),
                  ]),
          ),
        ],
      ]),
    );
  }

  Widget _trail(int saleId, String currentId) {
    final list = _trails[saleId];
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(6)),
      child: list == null
          ? const LoadingLine('Loading the sale’s payments…')
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text('SALE #$saleId · PAID ${list.length} TIMES',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF3730A3))),
              ),
              for (final p in [...list]..sort((a, b) => tStr(a['paymentDate']).compareTo(tStr(b['paymentDate']))))
                _trailCard(p, tStr(p['paymentId']) == currentId),
            ]),
    );
  }

  Widget _trailCard(Map p, bool isThis) {
    final count = tIntOrNull(p['allocationCount']) ?? 0;
    final after = p['balanceAfter'] == null ? null : tNum(p['balanceAfter']);
    String money(Object? v) => v == null ? '—' : _fmt(tNum(v));
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: isThis ? const Color(0xFF818CF8) : TColors.slate200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: paymentRef(p), style: const TextStyle(fontWeight: FontWeight.w500)),
              TextSpan(text: '  ${_dateOf(p['paymentDate'])}', style: const TextStyle(color: TColors.slate500)),
            ]), style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
          ),
          count > 1
              ? Text('across $count sales', style: const TextStyle(fontSize: 12, color: TColors.slate500))
              : Text(_fmt(tNum(p['amountApplied'] ?? p['totalAmount'])),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TColors.emerald700)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: Text('Before ${money(p['balanceBefore'])}', style: const TextStyle(fontSize: 12, color: TColors.slate500))),
          Text('After ${money(p['balanceAfter'])}',
              style: TextStyle(
                  fontSize: 12,
                  color: after == null ? TColors.slate500 : after <= 0 ? TColors.emerald700 : TColors.amber700)),
        ]),
        if (isReversedPayment(p))
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Reversed', style: TextStyle(fontSize: 11, color: TColors.slate400)),
          )
        else if (_canReverse)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size.fromHeight(34)),
              onPressed: () => _reverse(p),
              icon: const Icon(Icons.undo, size: 14),
              label: const Text('Reverse'),
            ),
          ),
      ]),
    );
  }
}

/// fmtDateTime: the business day, plus the clock time when the value has one.
String fmtDateTimeLike(Object? raw) {
  final s = tStr(raw);
  final day = formatShortDate(s);
  final m = RegExp(r'T(\d{2}):(\d{2})').firstMatch(s);
  if (m == null || (m[1] == '00' && m[2] == '00')) return day;
  return '$day, ${m[1]}:${m[2]}';
}
