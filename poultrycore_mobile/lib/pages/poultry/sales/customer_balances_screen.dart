import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../reports/report_format.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';
import 'balances_logic.dart';
import 'balances_widgets.dart';
import 'payments_received_screen.dart' show fmtDateTimeLike;
import 'sale_dialogs.dart';
import 'sales_screen.dart';
import '../reports/report_routes.dart' show openAppHref;

/// Poultry → Sales, Expenses & Money → Sales → Customer Balances, as
/// `components/balances/balances-page.tsx` (module "poultry", side
/// "customer"): who owes money, on which sales, and how to collect it — bulk
/// or per-sale payments, the statement and payment history. The phone layout
/// (one card per customer; Poultry has no pager on this page).
class CustomerBalancesScreen extends StatefulWidget {
  const CustomerBalancesScreen({super.key, required this.session, required this.company, this.side = BalanceSide.customer});

  /// Customer Balances, or (BalancesPage side "supplier") Supplier Balances.
  final BalanceSide side;
  final Session session;
  final Company company;

  @override
  State<CustomerBalancesScreen> createState() => _CustomerBalancesScreenState();
}

class _CustomerBalancesScreenState extends State<CustomerBalancesScreen> {
  BalanceSide get _side => widget.side;
  List<Map> _rows = [];
  Map? _summary;
  bool _loading = true;
  List<Map> _accounts = [];
  FarmMoney _fmt = const FarmMoney();

  int? _expanded;
  final Map<int, List<Map>> _docs = {};
  int? _docsLoading;

  final _search = TextEditingController();
  final _min = TextEditingController();
  String _status = 'All';
  String _from = '', _to = '';
  String _party = 'all';
  String _method = 'all';

  List<(int, String)> _partyOptions = [];
  Map<int, List<String>> _methodsByParty = {};
  List<String> _methodOptions = [];

  int _loadSeq = 0;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  /// pay / statement / reverse are permission keys on the web; the phone has
  /// no permission flags, so they are offered to everyone but Staff.
  bool get _can => (widget.company.role ?? '').toLowerCase() != 'staff';

  bool get _filtersEmpty =>
      _from.isEmpty && _to.isEmpty && _party == 'all' && _status == 'All' && _min.text.isEmpty && _search.text.trim().isEmpty;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _fmt = m);
    });
    _load();
    _loadMethods();
    _loadAccounts();
  }

  @override
  void dispose() {
    _search.dispose();
    _min.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    final empty = _filtersEmpty;
    setState(() => _loading = true);
    try {
      final r = await Future.wait([
        _api.get('/api/Poultry/${_side.balancesPath}', query: {
          'farmId': _farmId,
          if (_from.isNotEmpty) 'from': _from,
          if (_to.isNotEmpty) 'to': _to,
          if (_party != 'all') _side.partyParam: _party,
          'status': _status,
          if (_min.text.isNotEmpty) 'minBalance': _min.text,
          if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
        }),
        _api.get('/api/Poultry/${_side.balancesPath}/summary', query: {'farmId': _farmId}),
      ]);
      if (!mounted || seq != _loadSeq) return;
      final list = rowsOf(r[0]);
      setState(() {
        _rows = list;
        _summary = r[1] is Map ? r[1] as Map : null;
        // An unfiltered list IS every customer: the dropdown's options.
        if (empty) _partyOptions = [for (final p in list) (tIntOrNull(p['partyId']) ?? 0, tStr(p['partyName']))];
        _docs.clear();
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load ${_side.partyWord} balances', description: e.message, error: true);
    }
    if (mounted && seq == _loadSeq) setState(() => _loading = false);
  }

  /// Party → the methods their POSTED payments used. One read, refreshed only
  /// when a payment is posted or reversed.
  Future<void> _loadMethods() async {
    try {
      final res = await _api.get('/api/Poultry/${_side.paymentsPath}', query: {'farmId': _farmId});
      final byParty = <int, List<String>>{};
      final seen = <String>{};
      for (final p in rowsOf(res)) {
        if ((p['status'] ?? 'Posted') != 'Posted') continue;
        final m = tStr(p['paymentMethod']).trim();
        if (m.isEmpty) continue;
        seen.add(m);
        final pid = tIntOrNull(p['partyId']);
        if (pid == null) continue;
        final list = byParty.putIfAbsent(pid, () => []);
        if (!list.contains(m)) list.add(m);
      }
      if (mounted) {
        setState(() {
          _methodsByParty = byParty;
          _methodOptions = seen.toList()..sort();
        });
      }
    } on ApiException {
      if (mounted) {
        setState(() {
          _methodsByParty = {};
          _methodOptions = [];
        });
      }
    }
  }

  Future<void> _loadAccounts() async {
    try {
      final res = await _api.get('/api/Poultry/cash-accounts', query: {'farmId': _farmId});
      if (mounted) {
        setState(() => _accounts = [
              for (final a in rowsOf(res))
                if (a['isActive'] == true)
                  {
                    'id': a['poultryCashAccountId'],
                    'name': a['accountName'],
                    'currentBalance': a['currentBalance'],
                    'allowNegativeBalance': a['allowNegativeBalance'],
                  },
            ]);
      }
    } on ApiException {
      if (mounted) setState(() => _accounts = []);
    }
  }

  void _afterPayment() {
    setState(() => _expanded = null);
    _loadMethods();
    _load();
  }

  Future<void> _toggle(Map party) async {
    final pid = tIntOrNull(party['partyId']) ?? 0;
    if (_expanded == pid) {
      setState(() => _expanded = null);
      return;
    }
    setState(() => _expanded = pid);
    if (_docs.containsKey(pid)) return;
    setState(() => _docsLoading = pid);
    try {
      final res = await _api.get('/api/Poultry/${_side.balancesPath}/$pid/${_side.openLeaf}', query: {
        'farmId': _farmId,
        if (_from.isNotEmpty) 'from': _from,
        if (_to.isNotEmpty) 'to': _to,
        'status': _status,
      });
      if (mounted) setState(() => _docs[pid] = rowsOf(res));
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load open ${_side.docWord}s', description: e.message, error: true);
    }
    if (mounted) setState(() => _docsLoading = null);
  }

  Future<void> _pay(Map party, [Map? doc]) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => RecordPaymentScreen(
        session: widget.session,
        company: widget.company,
        party: party,
        single: doc,
        cashAccounts: _accounts,
        side: _side,
      ),
    ));
    if (ok == true) _afterPayment();
  }

  void _statement(Map party) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => StatementScreen(session: widget.session, company: widget.company, party: party, side: _side),
      ));

  void _history({Map? party, Map? doc}) => showPaymentHistory(context,
      session: widget.session,
      company: widget.company,
      partyId: party == null ? null : tIntOrNull(party['partyId']),
      partyName: party == null ? null : tStr(party['partyName']),
      documentType: doc == null ? null : tStr(doc['documentType']),
      documentId: doc == null ? null : tIntOrNull(doc['documentId']),
      canReverse: _can,
      onReversed: _afterPayment,
      side: _side);

  /// documentHref: a sale opens the Sales page focused on it; a flock batch
  /// its batch page; any other purchase the raw-material purchases tab.
  void _openDocument(Map d) {
    final id = tIntOrNull(d['documentId']);
    if (!_side.isCustomer) {
      final href = tStr(d['documentType']) == 'FlockBatch'
          ? '/flock-batch/${tStr(d['documentId'])}'
          : '/poultry-raw-materials?tab=purchases&purchaseId=${tStr(d['documentId'])}';
      openAppHref(context, widget.session, widget.company, href, label: _side.docTitle);
      return;
    }
    if (id == null) {
      trackerToast(context, 'No page for this record', description: '${d['documentType']} #${d['documentId']} has no detail page.');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SalesScreen(session: widget.session, company: widget.company, focusSaleId: id),
    ));
  }

  void _reset() {
    setState(() {
      _search.clear();
      _status = 'All';
      _from = '';
      _to = '';
      _min.clear();
      _party = 'all';
      _method = 'all';
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: _side.isCustomer ? '/customer-balances' : '/supplier-balances');
    final visible = _method == 'all'
        ? _rows
        : [for (final r in _rows) if ((_methodsByParty[tIntOrNull(r['partyId'])] ?? const []).contains(_method)) r];
    final s = _summary;
    final period = _from.isNotEmpty && _to.isNotEmpty ? rangeToPeriod(_from, _to) : 'custom';

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: Text(_side.title)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Row(children: [
              _side.isCustomer
                  ? const Icon(Icons.people_outline, size: 24, color: Color(0xFF0284C7))
                  : const Icon(Icons.account_balance_wallet_outlined, size: 24, color: TColors.amber600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_side.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              _side.isCustomer
                  ? 'Who owes money, which sales it is owed on, and how to collect it. Payments recorded here apply straight back to those sales.'
                  : 'Who we owe, which purchases it is owed on, and how to settle it. Payments recorded here apply straight back to those purchases.',
              style: const TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 14),
            if (s != null) ...[
              LayoutBuilder(builder: (context, c) {
                final w = (c.maxWidth - 10) / 2;
                Widget card(String label, String value, {bool danger = false}) => SizedBox(
                      width: w,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: TColors.slate200),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                          const SizedBox(height: 4),
                          Text(value,
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w600, color: danger ? TColors.red600 : TColors.slate900)),
                        ]),
                      ),
                    );
                final overdue = tNum(s['overdueBalance']);
                return Wrap(spacing: 10, runSpacing: 10, children: [
                  card(_side.isCustomer ? 'Total customer balance' : 'Total supplier balance', _fmt(tNum(s['totalBalance']))),
                  card(_side.isCustomer ? 'Customers owing' : 'Suppliers owed', '${tIntOrNull(s['partyCount']) ?? 0}'),
                  card(_side.isCustomer ? 'Overdue balance' : 'Overdue payables', _fmt(overdue), danger: overdue > 0),
                  card(_side.isCustomer ? 'Received today' : 'Paid today', _fmt(tNum(s['paymentsToday']))),
                  card(_side.isCustomer ? 'Largest balance' : 'Largest payable', _fmt(tNum(s['largestBalance']))),
                ]);
              }),
              if (tStr(s['largestBalanceParty']).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text.rich(TextSpan(children: [
                    const TextSpan(text: 'Largest balance: '),
                    TextSpan(text: tStr(s['largestBalanceParty']), style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate700)),
                  ]), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                ),
              const SizedBox(height: 14),
            ],
            TCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilterLabel(
                  'Search',
                  AppInput(controller: _search, hintText: '${_side.partyTitle} name or phone', onChanged: (_) => _load()),
                ),
                const SizedBox(height: 10),
                // Two filters to a row, so the card stays short.
                filterRow([
                FilterLabel(
                  _side.partyTitle,
                  AppSelect<String>(
                    value: _party,
                    items: [
                      AppSelectItem(value: 'all', label: 'All ${_side.partyWord}s'),
                      for (final (id, name) in _partyOptions) AppSelectItem(value: '$id', label: name),
                    ],
                    onChanged: (v) {
                      setState(() => _party = v ?? 'all');
                      _load();
                    },
                  ),
                ),
                FilterLabel(
                  'Payment method',
                  AppSelect<String>(
                    value: _method,
                    items: [
                      const AppSelectItem(value: 'all', label: 'Any method'),
                      for (final m in _methodOptions) AppSelectItem(value: m, label: m),
                    ],
                    onChanged: (v) => setState(() => _method = v ?? 'all'),
                  ),
                ),
                ]),
                const SizedBox(height: 10),
                filterRow([
                FilterLabel(
                  'Status',
                  AppSelect<String>(
                    value: _status,
                    items: [for (final st in balanceStatusFilters) AppSelectItem(value: st, label: balanceStatusLabel(st))],
                    onChanged: (v) {
                      setState(() => _status = v ?? 'All');
                      _load();
                    },
                  ),
                ),
                FilterLabel(
                  'Period',
                  AppSelect<String>(
                    value: period,
                    hintText: 'Select period',
                    items: [
                      for (final (_, opts) in periodGroups)
                        for (final (k, l) in opts) AppSelectItem(value: k, label: l),
                    ],
                    onChanged: (k) {
                      final r = k == null ? null : periodToRange(k);
                      // "custom" resolves to null — the typed dates stay.
                      if (r != null) {
                        setState(() {
                          _from = r.from;
                          _to = r.to;
                        });
                        _load();
                      }
                    },
                  ),
                ),
                ]),
                const SizedBox(height: 10),
                filterRow([
                  FilterLabel('From', FilterDate(value: _from, hint: 'From', onChanged: (v) {
                    setState(() => _from = v);
                    _load();
                  })),
                  FilterLabel('To', FilterDate(value: _to, hint: 'To', onChanged: (v) {
                    setState(() => _to = v);
                    _load();
                  })),
                ]),
                const SizedBox(height: 10),
                FilterLabel(
                  'Min balance',
                  AppInput(
                    controller: _min,
                    hintText: '0.00',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                    onChanged: (_) => _load(),
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
                  TextButton(onPressed: _reset, child: const Text('Reset')),
                  if (!_side.isCustomer || _can)
                    OutlinedButton.icon(
                      onPressed: () => _history(),
                      icon: const Icon(Icons.history, size: 16),
                      label: const Text('All payments'),
                    ),
                ]),
              ]),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
              child: _loading
                  ? const Padding(padding: EdgeInsets.all(24), child: LoadingLine('Loading…'))
                  : visible.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: _method != 'all' && _rows.isNotEmpty
                                ? Text.rich(
                                    TextSpan(children: [
                                      TextSpan(text: 'No ${_side.partyWord} has paid by '),
                                      TextSpan(text: _method, style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate700)),
                                      const TextSpan(text: ' under these filters.'),
                                    ]),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: TColors.slate500),
                                  )
                                : Text('Nothing outstanding. Every ${_side.docWord} is fully paid.',
                                    textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(children: [
                            for (var i = 0; i < visible.length; i++) ...[_card(visible[i], i), const SizedBox(height: 10)],
                          ]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(Map party, int idx) => _PartyCard(
        key: ValueKey('party-${party['partyId']}'),
        striped: idx.isEven,
        party: party,
        fmt: _fmt,
        open: _expanded == tIntOrNull(party['partyId']),
        docsLoading: _docsLoading == tIntOrNull(party['partyId']),
        docs: _docs[tIntOrNull(party['partyId'])],
        can: _can,
        onPay: () => _pay(party),
        onStatement: () => _statement(party),
        onHistory: () => _history(party: party),
        onToggle: () => _toggle(party),
        onPayDoc: (d) => _pay(party, d),
        onOpenDoc: _openDocument,
        onHistoryDoc: (d) => _history(party: party, doc: d),
        side: _side,
      );
}

class _PartyCard extends StatefulWidget {
  const _PartyCard({
    super.key,
    required this.striped,
    required this.party,
    required this.fmt,
    required this.open,
    required this.docsLoading,
    required this.docs,
    required this.can,
    required this.onPay,
    required this.onStatement,
    required this.onHistory,
    required this.onToggle,
    required this.onPayDoc,
    required this.onOpenDoc,
    required this.onHistoryDoc,
    required this.side,
  });
  final BalanceSide side;
  final bool striped;
  final Map party;
  final FarmMoney fmt;
  final bool open;
  final bool docsLoading;
  final List<Map>? docs;
  final bool can;
  final VoidCallback onPay, onStatement, onHistory, onToggle;
  final ValueChanged<Map> onPayDoc, onOpenDoc, onHistoryDoc;
  @override
  State<_PartyCard> createState() => _PartyCardState();
}

class _PartyCardState extends State<_PartyCard> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.party;
    final fmt = widget.fmt;
    final overdue = tNum(p['overdueAmount']);
    final n = tIntOrNull(p['openDocumentCount']) ?? 0;
    Widget kv(String l, String v) => Text.rich(TextSpan(children: [
          TextSpan(text: '$l ', style: const TextStyle(color: TColors.slate500)),
          TextSpan(text: v, style: const TextStyle(fontWeight: FontWeight.w500)),
        ]), style: const TextStyle(fontSize: 13));
    Widget box(String label, String value, Color bg, Color border, Color lc, Color vc) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: lc)),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: vc)),
          ]),
        );
    Widget btn(String label, IconData icon, VoidCallback on, {bool filled = false}) => filled
        ? FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(40)),
            onPressed: on,
            icon: Icon(icon, size: 16),
            label: Text(label),
          )
        : OutlinedButton.icon(
            style: OutlinedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size.fromHeight(40)),
            onPressed: on,
            icon: Icon(icon, size: 16),
            label: Text(label),
          );

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      decoration: BoxDecoration(
        color: widget.striped ? TColors.amber100 : Colors.white,
        border: Border.all(color: widget.striped ? TColors.amber300 : TColors.slate200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => _collapsed = !_collapsed),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tStr(p['partyName']), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
                  Text(tStr(p['contactPhone']).isEmpty ? 'No phone' : tStr(p['contactPhone']),
                      style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                ]),
              ),
              Icon(_collapsed ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up, size: 18, color: TColors.slate400),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: box('Balance', fmt(tNum(p['totalBalance'])), TColors.violet100, TColors.violet200,
                    const Color(0xFF4C1D95), const Color(0xFF4C1D95)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: overdue > 0
                    ? box('Overdue', fmt(overdue), TColors.red100, TColors.red300, TColors.red900, TColors.red700)
                    : box('Overdue', '—', TColors.slate100, TColors.slate300, TColors.slate700, TColors.slate400),
              ),
            ]),
          ]),
        ),
        if (!_collapsed) ...[
          const SizedBox(height: 12),
          const Divider(height: 1, color: TColors.slate200),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: kv('Open ${widget.side.docWord}s', '$n')),
            Expanded(child: kv('Oldest', tStr(p['oldestDocumentDate']).isEmpty ? '—' : fmtDateTimeLike(p['oldestDocumentDate']))),
          ]),
          const SizedBox(height: 4),
          kv('Last payment', tStr(p['lastPaymentDate']).isEmpty ? 'Never' : fmtDateTimeLike(p['lastPaymentDate'])),
          const SizedBox(height: 10),
          if (widget.can) ...[btn(widget.side.isCustomer ? 'Receive bulk payment' : 'Record bulk payment', Icons.account_balance_wallet_outlined, widget.onPay, filled: true), const SizedBox(height: 8)],
          Row(children: [
            if (widget.can) ...[Expanded(child: btn('Statement', Icons.description_outlined, widget.onStatement)), const SizedBox(width: 8)],
            Expanded(child: btn('History', Icons.history, widget.onHistory)),
          ]),
          const SizedBox(height: 8),
          btn(widget.open ? 'Hide open ${widget.side.docWord}s' : 'Show $n open ${widget.side.docWord}${n == 1 ? '' : 's'}',
              widget.open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, widget.onToggle),
          if (widget.open) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                border: Border.all(color: TColors.blue200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: widget.docsLoading || widget.docs == null
                  ? Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: LoadingLine('Loading open ${widget.side.docWord}s…'))
                  : widget.docs!.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text('No open ${widget.side.docWord}s match the current filters.',
                              style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                        )
                      : Column(children: [for (final d in widget.docs!) _doc(d, fmt, kv)]),
            ),
          ],
        ],
      ]),
    );
  }

  Widget _doc(Map d, FarmMoney fmt, Widget Function(String, String) kv) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.blue200), borderRadius: BorderRadius.circular(6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${d['reference'] ?? d['documentId']}', style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(tStr(d['label']).isNotEmpty ? tStr(d['label']) : (tStr(d['description']).isNotEmpty ? tStr(d['description']) : '—'),
                  overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
          ),
          d['isOverdue'] == true
              ? const TBadge('⚠ Overdue', bg: TColors.red600, fg: Colors.white)
              : TBadge(tStr(d['status']), bg: TColors.slate100, fg: TColors.slate800),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: kv('Date', fmtDateTimeLike(d['documentDate']))),
          Expanded(child: kv('Due', tStr(d['dueDate']).isEmpty ? '—' : fmtDateTimeLike(d['dueDate']))),
        ]),
        Row(children: [
          Expanded(child: kv('Total', fmt(tNum(d['totalAmount'])))),
          Expanded(child: kv('Paid', fmt(tNum(d['amountPaid'])))),
        ]),
        Row(children: [
          Expanded(child: kv('Balance', fmt(tNum(d['balance'])))),
          Expanded(child: kv('Age', '${tIntOrNull(d['ageDays']) ?? 0}d')),
        ]),
        const SizedBox(height: 8),
        if (widget.can) ...[
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
            onPressed: () => widget.onPayDoc(d),
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 16),
            label: Text(widget.side.isCustomer ? 'Receive payment' : 'Record payment'),
          ),
          const SizedBox(height: 6),
        ],
        Row(children: [
          Expanded(
            child: TextButton.icon(
              onPressed: () => widget.onOpenDoc(d),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open'),
            ),
          ),
          Expanded(
            child: TextButton.icon(
              onPressed: () => widget.onHistoryDoc(d),
              icon: const Icon(Icons.history, size: 16),
              label: const Text('History'),
            ),
          ),
        ]),
      ]),
    );
  }
}
