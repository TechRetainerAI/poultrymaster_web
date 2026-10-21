// Shared pieces of Sales → Payments received and Sales → Customer Balances:
// the web's ListFilters, the compact DataPagination, the Reverse payment
// dialog, Record payment (components/balances/record-payment-dialog.tsx) and
// the statement (components/balances/statement-dialog.tsx).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../shared/business_dates.dart';
import '../../shared/reason_select.dart' show ReasonSelect, reversalReasons;
import '../reports/report_export.dart';
import '../reports/report_format.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';
import 'balances_logic.dart';
import 'payments_received_screen.dart' show fmtDateTimeLike;

// ------------------------------------------------------------------ small parts

class LoadingLine extends StatelessWidget {
  const LoadingLine(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Row(children: [
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 8),
        Flexible(child: Text(text, style: const TextStyle(fontSize: 13, color: TColors.slate500))),
      ]);
}

class AllocationCard extends StatelessWidget {
  const AllocationCard({
    super.key,
    required this.title,
    required this.amount,
    required this.label,
    required this.date,
    required this.total,
    required this.before,
    required this.after,
  });
  final String title, amount, label, date, total, before, after;
  @override
  Widget build(BuildContext context) {
    const sm = TextStyle(fontSize: 12, color: TColors.slate500);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
          Text(amount, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        if (label.isNotEmpty) Text(label, style: sm, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Row(children: [Expanded(child: Text(date, style: sm)), Text('Total $total', style: sm)]),
        Row(children: [Expanded(child: Text('Before $before', style: sm)), Text('After $after', style: sm)]),
      ]),
    );
  }
}

/// components/ui/list-filters.tsx: Search, Period, From / To, the page's own
/// extras, and Clear (n) when search or dates are set.
class ListFiltersCard extends StatelessWidget {
  const ListFiltersCard({
    super.key,
    required this.search,
    required this.searchPlaceholder,
    required this.onSearch,
    required this.from,
    required this.to,
    required this.onDates,
    required this.onClear,
    this.extras = const [],
    this.searchOnly = false,
  });
  final TextEditingController search;
  final String searchPlaceholder;
  final VoidCallback onSearch;
  final String from, to;
  final void Function(String from, String to) onDates;
  final VoidCallback onClear;
  final List<Widget> extras;

  /// The web's `searchOnly`: the search box alone, no period or dates.
  final bool searchOnly;

  @override
  Widget build(BuildContext context) {
    final active = (search.text.isNotEmpty ? 1 : 0) + (from.isNotEmpty ? 1 : 0) + (to.isNotEmpty ? 1 : 0);
    final period = from.isNotEmpty && to.isNotEmpty ? rangeToPeriod(from, to) : 'custom';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilterLabel(
          'Search',
          AppInput(
            controller: search,
            hintText: searchPlaceholder,
            prefixIcon: const Icon(Icons.search, size: 18, color: TColors.slate400),
            onChanged: (_) => onSearch(),
          ),
        ),
        if (!searchOnly) ...[
        const SizedBox(height: 10),
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
              if (r != null) onDates(r.from, r.to);
            },
          ),
        ),
        const SizedBox(height: 10),
        filterRow([
          FilterLabel('From', FilterDate(value: from, hint: 'From', onChanged: (v) => onDates(v, to))),
          FilterLabel('To', FilterDate(value: to, hint: 'To', onChanged: (v) => onDates(from, v))),
        ]),
        ],
        // The page's own filters two to a row, so the card doesn't run the
        // length of the screen.
        for (var i = 0; i < extras.length; i += 2) ...[
          const SizedBox(height: 10),
          i + 1 < extras.length ? filterRow([extras[i], extras[i + 1]]) : extras[i],
        ],
        if (active > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.close, size: 14),
              label: Text('Clear ($active)'),
              style: TextButton.styleFrom(foregroundColor: TColors.slate500),
            ),
          ),
      ]),
    );
  }
}

/// DataPagination, compact: nothing under five rows, the size select, and
/// page links only when there is more than one page.
class CompactPager extends StatelessWidget {
  const CompactPager({
    super.key,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.onPage,
    required this.onPageSize,
  });
  final int total, page, pageSize;
  final ValueChanged<int> onPage, onPageSize;

  static List<Object> _numbers(int page, int total) {
    if (total <= 7) return [for (var i = 1; i <= total; i++) i];
    if (page <= 3) return [1, 2, 3, 4, 'ellipsis', total];
    if (page >= total - 2) return [1, 'ellipsis', total - 3, total - 2, total - 1, total];
    return [1, 'ellipsis', page - 1, page, page + 1, 'ellipsis', total];
  }

  @override
  Widget build(BuildContext context) {
    if (total < pageSizeOptions.first) return const SizedBox.shrink();
    final pages = total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize;
    final p = page.clamp(1, pages);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 130,
            child: AppSelect<int>(
              value: pageSize,
              items: [for (final n in pageSizeOptions) AppSelectItem(value: n, label: '$n / page')],
              onChanged: (v) {
                if (v != null) onPageSize(v);
              },
            ),
          ),
        ),
        if (pages > 1)
          Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, children: [
            TextButton.icon(
              onPressed: p == 1 ? null : () => onPage(p - 1),
              icon: const Icon(Icons.chevron_left, size: 18),
              label: const Text('Previous'),
            ),
            for (final n in _numbers(p, pages))
              n == 'ellipsis'
                  ? const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('…'))
                  : SizedBox(
                      width: 36,
                      height: 36,
                      child: n == p
                          ? OutlinedButton(style: OutlinedButton.styleFrom(padding: EdgeInsets.zero), onPressed: () {}, child: Text('$n'))
                          : TextButton(
                              style: TextButton.styleFrom(padding: EdgeInsets.zero),
                              onPressed: () => onPage(n as int),
                              child: Text('$n'),
                            ),
                    ),
            TextButton.icon(
              onPressed: p == pages ? null : () => onPage(p + 1),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.chevron_right, size: 18),
              label: const Text('Next'),
            ),
          ]),
      ]),
    );
  }
}

// ------------------------------------------------------------------ reverse

/// Payments received's "Reverse payment" dialog. Pops true when reversed.
class ReversePaymentDialog extends StatefulWidget {
  const ReversePaymentDialog({
    super.key,
    required this.session,
    required this.company,
    required this.target,
    required this.allocations,
    required this.fmt,
    this.api = '/api/Poultry',
  });
  final Session session;
  final Company company;
  final Map target;

  /// The module's route prefix (BalanceRail.api).
  final String api;

  /// The allocation already loaded for this payment, if any — as on the web,
  /// the dialog shows what is cached and does not fetch it.
  final List<Map>? allocations;
  final FarmMoney fmt;
  @override
  State<ReversePaymentDialog> createState() => _ReversePaymentDialogState();
}

class _ReversePaymentDialogState extends State<ReversePaymentDialog> {
  String _reason = '';
  bool _busy = false;
  String? _error;

  Future<void> _reverse() async {
    final t = widget.target;
    if (_reason.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.farmClient.post(
          '${widget.api}/customer-payments/${Uri.encodeComponent(tStr(t['paymentId']))}/reverse',
          body: {'farmId': widget.company.farmId, 'reason': _reason.trim(), 'reversedBy': widget.session.tokens.userId});
      if (!mounted) return;
      final n = tIntOrNull(t['allocationCount']) ?? 0;
      trackerToast(context, 'Payment reversed',
          description: '${widget.fmt(tNum(t['totalAmount']))} put back on $n sale${n == 1 ? '' : 's'}.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      // Kept in the window so the reason is not lost and they can try again.
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.target;
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.undo, color: TColors.red600),
        const SizedBox(width: 8),
        Flexible(child: Text('Reverse ${tStr(t['paymentNumber']).isEmpty ? 'this payment' : tStr(t['paymentNumber'])}?')),
      ]),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text(
              'The balance goes back onto every sale it was applied to and the cash movement is undone. The payment stays in the history, marked Reversed.',
              style: TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(tStr(t['partyName']).isEmpty ? 'Walk-in' : tStr(t['partyName']), style: const TextStyle(color: TColors.slate500))),
                Text(widget.fmt(tNum(t['totalAmount'])), style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 8),
              if (widget.allocations == null)
                const LoadingLine('Loading the sales it covers…')
              else
                for (final a in widget.allocations!)
                  Row(children: [
                    Expanded(child: Text('Sale #${a['documentId']}', style: const TextStyle(fontSize: 12, color: TColors.slate600))),
                    Text(widget.fmt(tNum(a['amountApplied'])), style: const TextStyle(fontSize: 12, color: TColors.slate600)),
                  ]),
            ]),
          ),
          const SizedBox(height: 12),
          FilterLabel('Reason *', ReasonSelect(options: reversalReasons, value: _reason, onChanged: (v) => setState(() => _reason = v))),
          if (_error != null) ...[const SizedBox(height: 10), TrackerBanner.error(_error!)],
        ]),
      ),
      actions: [
        OutlinedButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: TColors.red600),
          onPressed: _busy || _reason.trim().isEmpty ? null : _reverse,
          child: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Reverse payment'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ P&L (382)

/// Poultry (382): money paid on a debt recorded by hand goes on Profit & Loss
/// (a customer's as revenue, ours to a supplier as an operating expense). Only
/// that part is new to P&L, so the badge and the toggle show only when the
/// payment has some (`plAmount > 0`) and is not reversed.
bool paymentOnPL(Map row) => tNum(row['plAmount']) > 0 && (row['status'] ?? 'Posted') != 'Reversed';

/// "On P&L" / "Not on P&L" -- nothing for a payment with no debt in it.
Widget paymentPLBadge(Map row) {
  if (!paymentOnPL(row)) return const SizedBox.shrink();
  return row['excludedFromPL'] == true
      ? const TBadge('Not on P&L', bg: Colors.white, fg: TColors.slate500, border: TColors.slate300)
      : const TBadge('On P&L', bg: TColors.emerald50, fg: TColors.emerald800, border: TColors.emerald300);
}

/// Exclude from P&L / Include in P&L, with a confirmation. Owner / admin only
/// (usePermissions().isAdmin: anyone who is not plain staff). Null when the
/// button does not show.
Widget? paymentPLToggle(BuildContext context,
    {required Session session, required Company company, required Map row, required BalanceSide side, required VoidCallback onChanged}) {
  if ((company.role ?? '').toLowerCase() == 'staff' || !paymentOnPL(row)) return null;
  final exclude = row['excludedFromPL'] != true;
  return OutlinedButton(
    style: OutlinedButton.styleFrom(backgroundColor: Colors.white),
    onPressed: () async {
      final fmt = await FarmMoney.load(session, company);
      if (!context.mounted) return;
      final what = side.isCustomer ? 'revenue' : 'an operating expense';
      final ref = tStr(row['paymentNumber']).isNotEmpty ? tStr(row['paymentNumber']) : 'payment #${tStr(row['paymentId'])}';
      final amount = fmt(tNum(row['plAmount']));
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => _PLConfirm(
          title: exclude ? 'Keep this payment off Profit & Loss?' : 'Put this payment back on Profit & Loss?',
          body: exclude
              ? '$amount of $ref was paid on debts and counts as $what. Excluding it takes it off Profit & Loss; the payment, the debt and the cash are not changed.'
              : '$amount of $ref will count as $what on Profit & Loss again, on the payment date.',
          action: exclude ? 'Exclude from P&L' : 'Include in P&L',
          run: () => session.farmClient.post(
            '/api/Poultry/${side.paymentsPath}/${Uri.encodeComponent(tStr(row['paymentId']))}/pl-exclusion',
            body: {'farmId': company.farmId, 'exclude': exclude},
          ),
        ),
      );
      if (ok != true || !context.mounted) return;
      trackerToast(context, exclude ? 'Kept off Profit & Loss' : 'Back on Profit & Loss', description: '$ref · $amount');
      onChanged();
    },
    child: Text(exclude ? 'Exclude from P&L' : 'Include in P&L'),
  );
}

class _PLConfirm extends StatefulWidget {
  const _PLConfirm({required this.title, required this.body, required this.action, required this.run});
  final String title, body, action;
  final Future<Object?> Function() run;
  @override
  State<_PLConfirm> createState() => _PLConfirmState();
}

class _PLConfirmState extends State<_PLConfirm> {
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      await widget.run();
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      trackerToast(context, 'Could not change Profit & Loss', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: AlertDialog(
          scrollable: true,
          title: Text(widget.title),
          content: SizedBox(width: 420, child: Text(widget.body, style: const TextStyle(fontSize: 13, color: TColors.slate600))),
          actions: [
            OutlinedButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: _busy ? null : _go, child: Text(widget.action)),
          ],
        ),
      );
}

// ------------------------------------------------------------------ record customer / supplier payment

/// Record customer payment (Payments Received, 367) / Record supplier payment
/// (Supplier Payments, 370), poultry: pick who, then the ordinary payment form
/// on their open items. What is not applied pays an old debt from before the
/// system (383) unless the user keeps it as credit; applied to nothing it is an
/// advance. Returns true when a payment was posted.
Future<bool> recordPartyPayment(BuildContext context, {required Session session, required Company company, required BalanceSide side}) async {
  final picked = await showDialog<(int, String, List<Map>)>(
    context: context,
    builder: (_) => _PickParty(session: session, company: company, side: side),
  );
  if (picked == null || !context.mounted) return false;
  final (id, name, accounts) = picked;
  final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
    builder: (_) => RecordPaymentScreen(
      session: session,
      company: company,
      party: {'partyId': id, 'partyName': name},
      cashAccounts: accounts,
      side: side,
      sourceType: side.isCustomer ? 'PaymentsPage' : 'SupplierPayments',
      remainderAsOldDebt: true,
    ),
  ));
  return ok == true;
}

class _PickParty extends StatefulWidget {
  const _PickParty({required this.session, required this.company, required this.side});
  final Session session;
  final Company company;
  final BalanceSide side;
  @override
  State<_PickParty> createState() => _PickPartyState();
}

class _PickPartyState extends State<_PickParty> {
  List<(int, String)> _people = [];
  List<Map> _accounts = [];
  int? _id;

  bool get _customer => widget.side.isCustomer;

  @override
  void initState() {
    super.initState();
    final api = widget.session.farmClient;
    final idKey = _customer ? 'customerId' : 'supplierId';
    api.get(_customer ? '/api/Customer' : '/api/Supplier', query: {'userId': widget.session.tokens.userId ?? '', 'farmId': widget.company.farmId}).then((res) {
      final list = <(int, String)>[
        for (final c in rowsOf(res))
          if ((tIntOrNull(c[idKey] ?? (_customer ? c['id'] : null)) ?? 0) > 0 && tStr(c['name'] ?? (_customer ? c['customerName'] : null)).isNotEmpty)
            (tIntOrNull(c[idKey] ?? (_customer ? c['id'] : null))!, tStr(c['name'] ?? (_customer ? c['customerName'] : null))),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      if (mounted) setState(() => _people = list);
    }).catchError((Object _) {});
    api.get('/api/Poultry/cash-accounts', query: {'farmId': widget.company.farmId}).then((res) {
      final list = [
        for (final a in rowsOf(res))
          if (a['isActive'] == true)
            {
              'id': tIntOrNull(a['poultryCashAccountId']),
              'name': tStr(a['accountName']),
              'currentBalance': a['currentBalance'],
              'allowNegativeBalance': a['allowNegativeBalance'],
            },
      ];
      if (mounted) setState(() => _accounts = list);
    }).catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final word = _customer ? 'customer' : 'supplier';
    return AlertDialog(
      scrollable: true,
      title: Text('Record $word payment'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            _customer
                ? 'Choose who paid. You can then apply the money to their open sales; whatever is not applied is kept as their credit.'
                : 'Choose who you paid. You can then apply the money to what you owe them; whatever is not applied is kept as supplier credit.',
            style: const TextStyle(fontSize: 13, color: TColors.slate500),
          ),
          const SizedBox(height: 12),
          FilterLabel(
            _customer ? 'Customer *' : 'Supplier *',
            AppSelect<int>(
              value: _id,
              hintText: _people.isNotEmpty ? 'Choose the $word' : 'Loading…',
              items: [for (final (id, name) in _people) AppSelectItem(value: id, label: name)],
              onChanged: (v) => setState(() => _id = v),
            ),
          ),
        ]),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _id == null
              ? null
              : () => Navigator.pop(context, (_id!, _people.firstWhere((p) => p.$1 == _id).$2, _accounts)),
          child: const Text('Next'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ record payment

/// "Receive bulk payment" (every open sale of the customer) or "Receive
/// payment" (one open sale, [single]). Pops true when posted.
class RecordPaymentScreen extends StatefulWidget {
  const RecordPaymentScreen({
    super.key,
    required this.session,
    required this.company,
    required this.party,
    required this.cashAccounts,
    this.single,
    this.side = BalanceSide.customer,
    this.sourceType,
    this.api = '/api/Poultry',
    this.remainderAsOldDebt = false,
  });
  final Session session;
  final Company company;
  final Map party;
  final Map? single;
  final BalanceSide side;

  /// 383 (poultry: Record customer / supplier payment on Payments Received):
  /// money not applied to anything paid something owed from before the system,
  /// unless the user keeps it as credit.
  final bool remainderAsOldDebt;

  /// The module's route prefix (BalanceRail.api).
  final String api;

  /// Where the payment was entered from; the side's balances page by default
  /// (the Expenses page posts as `ExpenseEntry`).
  final String? sourceType;

  /// Active accounts: (id, name, currentBalance).
  final List<Map> cashAccounts;
  @override
  State<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends State<RecordPaymentScreen> {
  List<Map> _docs = [];
  bool _loading = false;
  bool _posting = false;
  final _amount = TextEditingController();
  late String _date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  String _method = 'Cash';
  int? _account;
  final _ref = TextEditingController();
  final _notes = TextEditingController();
  Map<String, num> _alloc = {};
  final Map<String, TextEditingController> _lineCtl = {};
  bool _touched = false;
  FarmMoney _fmt = const FarmMoney();

  /// 382: money on a debt is on Profit & Loss unless the owner / an admin says not.
  bool _countOnPL = true;

  /// 383: the leftover is an old debt by default; the user can keep it as credit.
  bool _keepAsCredit = false;

  /// 367 / 370: a poultry payment need not be applied in full -- the rest is
  /// kept as the customer's / supplier's credit (applied to nothing = an advance).
  bool get _allowUnallocated => widget.api == '/api/Poultry';
  String get _creditWord => widget.side.isCustomer ? 'customer credit' : 'supplier credit';

  /// usePermissions().isAdmin: anyone who is not plain staff.
  bool get _isAdmin => (widget.company.role ?? '').toLowerCase() != 'staff';

  /// 382: the part paid on debts recorded by hand -- the only part new to P&L.
  num get _recordedDebtAllocated => !_allowUnallocated
      ? 0
      : _docs
          .where((d) => d['documentType'] == 'CustomerDebt' || d['documentType'] == 'SupplierDebt')
          .fold<num>(0, (t, d) => t + (_alloc[docKey(d)] ?? 0));

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _fmt = m);
    });
    final s = widget.single;
    if (s != null) {
      _docs = [s];
      _amount.text = tNum(s['balance']).toStringAsFixed(2);
      _alloc = {docKey(s): tNum(s['balance'])};
      _account = tIntOrNull(s['cashAccountId']);
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    _notes.dispose();
    for (final c in _lineCtl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.session.farmClient.get(
          '${widget.api}/${widget.side.balancesPath}/${widget.party['partyId']}/${widget.side.openLeaf}',
          query: {'farmId': widget.company.farmId});
      if (mounted) setState(() => _docs = rowsOf(res));
    } on ApiException catch (e) {
      if (mounted) {
        trackerToast(context, 'Could not load open items', description: e.message, error: true);
        Navigator.pop(context, false);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Map? get _acc => widget.cashAccounts.where((a) => tIntOrNull(a['id']) == _account).firstOrNull;
  bool get _overdraws => paymentOverdraws(widget.side, _acc, num.tryParse(_amount.text) ?? 0);

  TextEditingController _ctl(Map d) {
    final k = docKey(d);
    final c = _lineCtl.putIfAbsent(k, () => TextEditingController());
    final v = _alloc[k];
    final want = v == null ? '' : _plain(v);
    if (c.text != want && num.tryParse(c.text) != v) c.text = want;
    return c;
  }

  static String _plain(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Single-document mode has no grid to edit, so the one line tracks the amount.
  void _changeAmount(String raw) {
    setState(() {
      final s = widget.single;
      if (s == null) return;
      _touched = true;
      final v = num.tryParse(raw);
      // 367: paying more than the line owes keeps the rest as credit.
      final applied = _allowUnallocated && v != null && v > tNum(s['balance']) ? tNum(s['balance']) : v;
      _alloc = raw.isEmpty || v == null || v == 0 ? {} : {docKey(s): applied!};
    });
  }

  void _setLine(Map d, String raw) {
    setState(() {
      _touched = true;
      final v = num.tryParse(raw);
      if (raw.isEmpty || v == null || v == 0) {
        _alloc.remove(docKey(d));
      } else {
        _alloc[docKey(d)] = v;
      }
    });
  }

  Future<void> _submit(AllocationValidation v, {required num debtAllocated, required num oldDebt}) async {
    setState(() => _touched = true);
    if (!v.ok || _overdraws) return;
    setState(() => _posting = true);
    final side = widget.side;
    try {
      await widget.session.farmClient.post('${widget.api}/${side.paymentsPath}', body: {
        'partyId': tIntOrNull(widget.party['partyId']),
        'amount': num.tryParse(_amount.text) ?? 0,
        'paymentDate': entryTimestamp(_date),
        'paymentMethod': _method,
        'cashAccountId': _account,
        'reference': _ref.text.trim().isEmpty ? null : _ref.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'sourceType': widget.sourceType ?? side.sourceType,
        'allocations': [
          for (final d in _docs)
            if ((_alloc[docKey(d)] ?? 0) > 0)
              {
                // 369: a customer debt goes as its own document type, never as a sale id.
                'saleId': side.isCustomer && d['documentType'] != 'CustomerDebt' ? tIntOrNull(d['documentId']) : null,
                'documentType': d['documentType'],
                'documentId': tIntOrNull(d['documentId']),
                'amount': _alloc[docKey(d)],
              },
        ],
        'farmId': widget.company.farmId,
        'createdBy': widget.session.tokens.userId,
        'excludeFromPL': debtAllocated > 0 && !_countOnPL,
        'remainderAsOldDebt': oldDebt > 0,
      });
      if (!mounted) return;
      trackerToast(context, side.isCustomer ? 'Payment received' : 'Payment recorded',
          description: '${_fmt(num.tryParse(_amount.text) ?? 0)} applied across ${_alloc.length} item(s).');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _posting = false);
        trackerToast(context, side.isCustomer ? 'Could not receive payment' : 'Could not record payment', description: e.message, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.single;
    final amount = num.tryParse(_amount.text) ?? 0;
    // Customer payments credit the sale's own account, so it is optional there;
    // a supplier payment has to name the account the money left.
    final v = validateAllocations(amount, _docs, _alloc,
        cashAccountRequired: widget.side.cashAccountRequired, cashAccountId: _account, allowUnallocated: _allowUnallocated);
    // 383: what is left over pays an old debt, unless kept as credit.
    final oldDebt = widget.remainderAsOldDebt && _allowUnallocated && !_keepAsCredit && v.unallocated > 0 ? v.unallocated : 0;
    final debtAllocated = _recordedDebtAllocated + oldDebt;
    final leftoverWord = oldDebt > 0 ? (widget.side.isCustomer ? 'old customer debt' : 'old supplier debt') : _creditWord;
    final leftoverLine = '${_fmt(v.unallocated)} ${oldDebt > 0 ? 'pays an' : 'kept as'} $leftoverWord';
    final overdraws = _overdraws;
    final allocated = totalAllocated(_alloc);
    // With the grid hidden, a line problem (e.g. paying more than the balance)
    // has nowhere else to show, so every problem goes in the alert.
    final blocking = s != null ? [for (final p in v.problems) p.$2] : v.blocking;
    final money = TextInputType.numberWithOptions(decimal: true);
    final moneyFmt = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))];

    return Scaffold(
      appBar: AppBar(title: Text(widget.side.payTitle(single: s != null))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
        children: [
          Text(
            '${widget.party['partyName']} · '
            '${s != null ? '${s['reference'] ?? s['documentId']} · ${_fmt(tNum(s['balance']))} outstanding' : '${_fmt(totalOpenBalance(_docs))} outstanding across ${_docs.length} open item(s)'}',
            style: const TextStyle(fontSize: 13, color: TColors.slate500),
          ),
          const SizedBox(height: 14),
          FilterLabel(
            'Payment amount',
            AppInput(
              controller: _amount,
              hintText: '0.00',
              keyboardType: money,
              inputFormatters: moneyFmt,
              onChanged: _changeAmount,
            ),
          ),
          const SizedBox(height: 10),
          FilterLabel(
            'Payment date',
            AppDateField(
              value: businessDateAsDateTime(_date),
              onChanged: (d) => setState(() => _date = d == null ? '' : isoDay(d)),
            ),
          ),
          const SizedBox(height: 10),
          FilterLabel(
            'Payment method',
            AppSelect<String>(
              value: _method,
              items: [for (final m in balancePaymentMethods) AppSelectItem(value: m, label: m)],
              onChanged: (m) => setState(() => _method = m ?? _method),
            ),
          ),
          const SizedBox(height: 10),
          FilterLabel(
            widget.side.isCustomer ? 'Cash account (optional)' : 'Cash account',
            AppSelect<int>(
              value: widget.cashAccounts.any((a) => tIntOrNull(a['id']) == _account) ? _account : null,
              hintText: 'Select account',
              items: [
                for (final a in widget.cashAccounts)
                  AppSelectItem(
                    value: tIntOrNull(a['id'])!,
                    label: '${a['name']}${a['currentBalance'] != null ? ' · ${_fmt(tNum(a['currentBalance']))}' : ''}',
                  ),
              ],
              onChanged: (id) => setState(() => _account = id),
            ),
          ),
          const SizedBox(height: 10),
          FilterLabel('Reference', AppInput(controller: _ref, hintText: 'Optional')),
          const SizedBox(height: 10),
          FilterLabel('Notes', AppInput(controller: _notes, hintText: 'Optional', minLines: 1, maxLines: 4)),
          const SizedBox(height: 12),
          if (s != null)
            // Single-document mode: nothing to choose, so a summary line stands
            // in for the table. It still posts as a one-line allocation.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Applies to '),
                  TextSpan(text: '${s['reference'] ?? s['documentId']}', style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
                  if (tStr(s['label']).isNotEmpty) TextSpan(text: ' · ${s['label']}'),
                ]), style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                const SizedBox(height: 2),
                Text.rich(TextSpan(children: [
                  TextSpan(text: 'Balance ${_fmt(tNum(s['balance']))} → '),
                  TextSpan(
                    text: _fmt(balanceAfterAllocation(s, _alloc)),
                    style: TextStyle(fontWeight: FontWeight.w500, color: balanceAfterAllocation(s, _alloc) < 0 ? TColors.red600 : TColors.slate900),
                  ),
                  const TextSpan(text: ' after this payment'),
                  if (_allowUnallocated && v.unallocated > 0)
                    TextSpan(text: ' · $leftoverLine', style: const TextStyle(color: Color(0xFF1D4ED8))),
                ]), style: const TextStyle(fontSize: 13, color: TColors.slate500)),
              ]),
            )
          else ...[
          const Divider(height: 1),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            OutlinedButton.icon(
              onPressed: _amount.text.isEmpty || _loading
                  ? null
                  : () => setState(() {
                        _touched = true;
                        _alloc = autoAllocateOldestFirst(amount, _docs);
                      }),
              icon: const Icon(Icons.auto_fix_high, size: 16),
              label: const Text('Auto-allocate oldest first'),
            ),
            TextButton.icon(
              onPressed: _loading
                  ? null
                  : () => setState(() {
                        _touched = true;
                        _alloc = {};
                      }),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Clear'),
            ),
          ]),
          const SizedBox(height: 6),
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'Allocated ', style: TextStyle(color: TColors.slate500)),
            TextSpan(text: _fmt(allocated), style: const TextStyle(fontWeight: FontWeight.w500)),
            TextSpan(text: ' / ${_fmt(amount)}', style: const TextStyle(color: TColors.slate400)),
            if (v.unallocated != 0)
              TextSpan(
                text: v.unallocated > 0
                    ? (_allowUnallocated ? '  ($leftoverLine)' : '  (${_fmt(v.unallocated)} unallocated)')
                    : '  (${_fmt(-v.unallocated)} over)',
                style: TextStyle(
                    color: v.unallocated > 0 ? (_allowUnallocated ? const Color(0xFF1D4ED8) : TColors.amber600) : TColors.red600),
              ),
          ]), style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
            child: _loading
                ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading open items…'))
                : _docs.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(28),
                        child: Center(child: Text('Nothing outstanding for this ${widget.side.partyWord}.', style: const TextStyle(color: TColors.slate500))),
                      )
                    : Column(children: [for (final d in _docs) _line(d, v, money, moneyFmt)]),
          ),
          ],
          if (widget.remainderAsOldDebt && _allowUnallocated && v.unallocated > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                border: Border.all(color: TColors.blue200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                  '${_fmt(v.unallocated)} is not applied to anything listed. '
                  '${_keepAsCredit ? 'It will be kept as $_creditWord (an advance) -- not on Profit & Loss until it is used.' : 'It will be recorded as ${widget.side.isCustomer ? 'a debt the customer owed' : 'a debt we owed the supplier'} from before the system, paid now.'}',
                  style: const TextStyle(fontSize: 13, color: TColors.blue900),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () => setState(() => _keepAsCredit = !_keepAsCredit),
                  child: Row(children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(value: _keepAsCredit, onChanged: (x) => setState(() => _keepAsCredit = x == true)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Keep it as $_creditWord (an advance) instead', style: const TextStyle(fontSize: 12, color: TColors.blue900)),
                    ),
                  ]),
                ),
              ]),
            ),
          ],
          if (debtAllocated > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: TColors.emerald50,
                border: Border.all(color: TColors.emerald200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: _isAdmin
                  ? InkWell(
                      onTap: () => setState(() => _countOnPL = !_countOnPL),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(value: _countOnPL, onChanged: (x) => setState(() => _countOnPL = x == true)),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              'Count the ${_fmt(debtAllocated)} paid on debts on Profit & Loss as ${widget.side.isCustomer ? 'revenue' : 'an operating expense'}.',
                              style: const TextStyle(fontSize: 13, color: TColors.emerald900),
                            ),
                            const Text(
                              'Untick to keep it off Profit & Loss. You can change this later from the payments list.',
                              style: TextStyle(fontSize: 12, color: TColors.emerald800),
                            ),
                          ]),
                        ),
                      ]),
                    )
                  : Text(
                      'The ${_fmt(debtAllocated)} paid on debts goes on Profit & Loss as ${widget.side.isCustomer ? 'revenue' : 'an operating expense'}.',
                      style: const TextStyle(fontSize: 13, color: TColors.emerald900),
                    ),
            ),
          ],
          if (_touched && (blocking.isNotEmpty || overdraws)) ...[
            const SizedBox(height: 12),
            TrackerBanner.error('', spans: [
              for (var i = 0; i < blocking.length; i++) TextSpan(text: '${i > 0 ? '\n' : ''}• ${blocking[i]}'),
              if (overdraws)
                TextSpan(
                    text: '${blocking.isNotEmpty ? '\n' : ''}• ${_acc?['name']} holds ${_fmt(tNum(_acc?['currentBalance']))} — this payment would overdraw it.'),
            ]),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                onPressed: _posting ? null : () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                onPressed: _posting || _loading || !v.ok ? null : () => _submit(v, debtAllocated: debtAllocated, oldDebt: oldDebt),
                child: _posting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(widget.side.isCustomer ? 'Receive payment' : 'Record payment'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _line(Map d, AllocationValidation v, TextInputType kb, List<TextInputFormatter> f) {
    final key = docKey(d);
    final over = v.overAllocated.containsKey(key);
    const sm = TextStyle(fontSize: 12, color: TColors.slate500);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: over ? TColors.red50 : null,
        border: const Border(bottom: BorderSide(color: TColors.slate100)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('${d['reference'] ?? d['documentId']}', style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Text(fmtDateTimeLike(d['documentDate']), style: sm),
          if (d['isOverdue'] == true) ...[
            const SizedBox(width: 6),
            TBadge('${tIntOrNull(d['ageDays']) ?? 0}d', bg: TColors.red100, fg: TColors.red700),
          ],
        ]),
        Text(tStr(d['label']).isEmpty ? '—' : tStr(d['label']), style: sm),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: Text('Total ${_fmt(tNum(d['totalAmount']))}', style: sm)),
          Expanded(child: Text('Paid ${_fmt(tNum(d['amountPaid']))}', style: sm)),
          Text('Balance ${_fmt(tNum(d['balance']))}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          const Text('Amount to apply', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          Expanded(
            child: AppInput(
              controller: _ctl(d),
              hintText: '0.00',
              keyboardType: kb,
              inputFormatters: f,
              onChanged: (raw) => _setLine(d, raw),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Balance after ${_fmt(balanceAfterAllocation(d, _alloc))}', textAlign: TextAlign.right, style: sm),
        for (final p in v.problems.where((p) => p.$1 == key))
          Text(p.$2, style: const TextStyle(fontSize: 12, color: TColors.red600)),
      ]),
    );
  }
}

// ------------------------------------------------------------------ statement

/// "Customer statement": opening balance, every sale and payment in the
/// window, and a running balance. Print shares a PDF.
class StatementScreen extends StatefulWidget {
  const StatementScreen(
      {super.key, required this.session, required this.company, required this.party, this.side = BalanceSide.customer, this.api = '/api/Poultry'});
  final Session session;
  final Company company;
  final Map party;
  final BalanceSide side;

  /// The module's route prefix (BalanceRail.api).
  final String api;
  @override
  State<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends State<StatementScreen> {
  String get _closingLabel => widget.side.isCustomer ? 'Closing balance owed to us' : 'Closing balance we owe';
  List<Map> _lines = [];
  bool _loading = true;
  String _from = '', _to = '';
  String? _openPayment;
  final Map<String, List<Map>> _alloc = {};
  FarmMoney _fmt = const FarmMoney();

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _fmt = m);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.session.farmClient.get('${widget.api}/${widget.side.statementLeaf}/${widget.party['partyId']}/statement', query: {
        'farmId': widget.company.farmId,
        if (_from.isNotEmpty) 'from': _from,
        if (_to.isNotEmpty) 'to': _to,
      });
      if (mounted) setState(() => _lines = rowsOf(res));
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load statement', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle(String id) async {
    if (_openPayment == id) {
      setState(() => _openPayment = null);
      return;
    }
    setState(() => _openPayment = id);
    if (_alloc.containsKey(id)) return;
    try {
      final res = await widget.session.farmClient.get('${widget.api}/${widget.side.paymentsPath}/${Uri.encodeComponent(id)}',
          query: {'farmId': widget.company.farmId});
      if (mounted) setState(() => _alloc[id] = res is Map ? rowsOf(res['allocations']) : []);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load the allocation', description: e.message, error: true);
    }
  }

  num get _closing => _lines.isNotEmpty ? tNum(_lines.last['runningBalance']) : 0;

  Future<void> _print() => ReportExport.sharePdf(ReportDocument(
        title: widget.side.statementTitle,
        filename: '${widget.side.partyWord}-statement',
        farmName: widget.company.name,
        fromDate: _from.isEmpty ? null : _from,
        toDate: _to.isEmpty ? null : _to,
        subtitle: '${widget.party['partyName']}${tStr(widget.party['contactPhone']).isNotEmpty ? ' · ${widget.party['contactPhone']}' : ''}',
        sections: [
          ReportSection(
            columns: [
              ReportColumn('Date'),
              ReportColumn('Type'),
              ReportColumn('Reference'),
              ReportColumn('Description'),
              ReportColumn('Source'),
              ReportColumn(widget.side.isCustomer ? 'Charges' : 'Billed', right: true),
              ReportColumn(widget.side.isCustomer ? 'Payments' : 'Paid', right: true),
              ReportColumn('Balance', right: true),
            ],
            rows: [
              for (final l in _lines)
                [
                  tStr(l['entryDate']).isEmpty ? '—' : fmtDateTimeLike(l['entryDate']),
                  l['entryType'] == 'OpeningBalance' ? 'Opening' : tStr(l['entryType']),
                  tStr(l['reference']).isEmpty ? '—' : tStr(l['reference']),
                  tStr(l['description']).isEmpty ? '—' : tStr(l['description']),
                  statementSourceLabel(l['sourceType']),
                  tNum(l['debit']) != 0 ? _fmt(tNum(l['debit'])) : '—',
                  tNum(l['credit']) != 0 ? _fmt(tNum(l['credit'])) : '—',
                  _fmt(tNum(l['runningBalance'])),
                ],
            ],
            totals: ['', '', '', '', '', '', _closingLabel, _fmt(_closing)],
          ),
        ],
      ));

  @override
  Widget build(BuildContext context) {
    final p = widget.party;
    const sm = TextStyle(fontSize: 12, color: TColors.slate500);
    return Scaffold(
      appBar: AppBar(title: Text(widget.side.statementTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          Text('${p['partyName']}${tStr(p['contactPhone']).isNotEmpty ? ' · ${p['contactPhone']}' : ''}',
              style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 12),
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
          if (_from.isNotEmpty || _to.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _from = '';
                    _to = '';
                  });
                  _load();
                },
                child: const Text('All history'),
              ),
            ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
            child: _loading
                ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading statement…'))
                : _lines.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(child: Text('Nothing to show for this period.', style: TextStyle(color: TColors.slate500))),
                      )
                    : Column(children: [
                        for (final l in _lines) _line(l, sm),
                        Container(
                          color: TColors.slate50,
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            Expanded(
                              child: Text(_closingLabel, style: const TextStyle(fontWeight: FontWeight.w500)),
                            ),
                            Text(_fmt(_closing), style: const TextStyle(fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _loading || _lines.isEmpty ? null : _print,
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Print'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))),
          ]),
        ],
      ),
    );
  }

  Widget _line(Map l, TextStyle sm) {
    final pid = tStr(l['paymentId']);
    final drill = pid.isNotEmpty && (tIntOrNull(l['allocationCount']) ?? 1) > 1;
    final open = pid.isNotEmpty && _openPayment == pid;
    final opening = l['entryType'] == 'OpeningBalance';
    final debit = tNum(l['debit']), credit = tNum(l['credit']);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: opening ? TColors.slate50 : null,
        border: const Border(bottom: BorderSide(color: TColors.slate100)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('${opening ? 'Opening' : l['entryType']}  ·  ${tStr(l['reference']).isEmpty ? '—' : l['reference']}',
                style: TextStyle(fontWeight: opening ? FontWeight.w600 : FontWeight.w500)),
          ),
          Text(_fmt(tNum(l['runningBalance'])), style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        Text(tStr(l['entryDate']).isEmpty ? '—' : fmtDateTimeLike(l['entryDate']), style: sm),
        const SizedBox(height: 2),
        drill
            ? InkWell(
                onTap: () => _toggle(pid),
                child: Row(children: [
                  Icon(open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 16, color: const Color(0xFF0369A1)),
                  Expanded(
                    child: Text(tStr(l['description']).isEmpty ? '—' : tStr(l['description']),
                        style: const TextStyle(fontSize: 13, color: Color(0xFF0369A1))),
                  ),
                ]),
              )
            : Text(tStr(l['description']).isEmpty ? '—' : tStr(l['description']), style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 2),
        Text('Source: ${statementSourceLabel(l['sourceType'])}', style: sm),
        Wrap(spacing: 12, children: [
          Text('Charges ${debit != 0 ? _fmt(debit) : '—'}', style: sm),
          Text('Payments ${credit != 0 ? _fmt(credit) : '—'}', style: sm),
        ]),
        if (open) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            color: const Color(0x99F8FAFC),
            child: !_alloc.containsKey(pid)
                ? const LoadingLine('Loading allocation…')
                : Column(children: [
                    for (final a in _alloc[pid]!)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Wrap(spacing: 12, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Text.rich(TextSpan(children: [
                            TextSpan(text: 'Sale #${a['documentId']}', style: const TextStyle(fontWeight: FontWeight.w500)),
                            if (tStr(a['label']).isNotEmpty) TextSpan(text: '  ${a['label']}', style: const TextStyle(color: TColors.slate500)),
                          ]), style: const TextStyle(fontSize: 13)),
                          Text('${_fmt(tNum(a['balanceBefore']))} → ${_fmt(tNum(a['balanceAfter']))}',
                              style: const TextStyle(fontSize: 12, color: TColors.slate600)),
                          Text(_fmt(tNum(a['amountApplied'])), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                  ]),
          ),
        ],
      ]),
    );
  }
}
