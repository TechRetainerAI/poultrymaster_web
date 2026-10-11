// Settings → Billing: app/business-office/billing/page.tsx with its
// BillingPanel (components/business-office/billing-panel.tsx). One
// subscription across every company: notices, the hero with Pay this period,
// the companies on the bill, invoices and payments, Change billing market and
// "Why this price?". Checkout opens the provider's page in-app and returns
// through the same ?billing=success&reference= the web verifies.

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/api_client.dart';
import '../../config/env.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tBool;
import '../poultry/trackers/tracker_widgets.dart';

const billingReturnPath = '/business-office/billing';

String billingMoney(Object? v, Object? currency) {
  if (v == null) return '—';
  final n = tNum(v);
  final parts = n.toStringAsFixed(2).split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  return '${tStr(currency)} $whole.${parts[1]}';
}

String _date(Object? v) {
  final d = DateTime.tryParse(tStr(v))?.toLocal();
  return d == null ? '' : '${d.month}/${d.day}/${d.year}';
}

String _dateTime(Object? v) {
  final d = DateTime.tryParse(tStr(v))?.toLocal();
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${d.month}/${d.day}/${d.year}, $h:${two(d.minute)}:${two(d.second)} ${d.hour < 12 ? 'AM' : 'PM'}';
}

String _thousands(Object? v) {
  final n = tNum(v);
  final s = n == n.roundToDouble() ? '${n.toInt()}' : '$n';
  final parts = s.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  return parts.length > 1 ? '$whole.${parts[1]}' : whole;
}

Widget tierBadge(Object? name) {
  final n = tStr(name);
  if (n.isEmpty) return const Text('—', style: TextStyle(color: TColors.slate400));
  final (bg, fg) = switch (n.toLowerCase()) {
    'growth' => (const Color(0xFFEEF2FF), const Color(0xFF4338CA)),
    'business' => (const Color(0xFFF5F3FF), const Color(0xFF6D28D9)),
    'enterprise' => (TColors.amber50, const Color(0xFF92400E)),
    _ => (TColors.slate50, TColors.slate600),
  };
  return TBadge(n, bg: bg, fg: fg);
}

Widget billingStatusBadge(String status) {
  final (bg, fg) = switch (status.toLowerCase()) {
    'active' || 'paid' || 'succeeded' => (const Color(0xFFF0FDF4), const Color(0xFF15803D)),
    'trial' || 'open' || 'evaluation' => (TColors.amber50, const Color(0xFF92400E)),
    'pastdue' || 'failed' || 'suspended' => (TColors.red50, TColors.red700),
    _ => (TColors.slate50, TColors.slate600),
  };
  return TBadge(status, bg: bg, fg: fg);
}

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key, required this.session, required this.company, this.billing, this.reference});
  final Session session;
  final Company company;

  /// The checkout return (`?billing=success&reference=` / `?billing=cancel`).
  final String? billing, reference;
  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  Map? _summary;
  List<Map> _invoices = [], _payments = [];
  bool _loading = true, _checkoutBusy = false, _verifying = false;
  String _loadError = '';
  int _tab = 0;

  ApiClient get _api => widget.session.farmClient;
  String get _userId => widget.session.tokens.userId ?? '';
  Map<String, String> get _q => {'userId': _userId};

  @override
  void initState() {
    super.initState();
    _reload();
    if (widget.billing == 'success' && (widget.reference ?? '').isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _verify(widget.reference!));
    } else if (widget.billing == 'cancel') {
      WidgetsBinding.instance.addPostFrameCallback((_) => trackerToast(context, 'Checkout cancelled', description: 'No changes were made.'));
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _loadError = '';
    });
    try {
      final r = await Future.wait([
        _api.get('/api/PlatformBilling/summary', query: _q),
        _api.get('/api/PlatformBilling/invoices', query: _q),
        _api.get('/api/PlatformBilling/payments', query: _q),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = r[0] is Map ? r[0] as Map : null;
        _invoices = rowsOf(r[1]);
        _payments = rowsOf(r[2]);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message.isNotEmpty ? e.message : 'Could not load billing.');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _verify(String reference) async {
    setState(() => _verifying = true);
    var ok = false;
    var message = 'Verification failed.';
    try {
      final b = await _api.get('/api/PlatformBilling/verify', query: {..._q, 'reference': reference});
      ok = b is Map && b['ok'] == true;
      if (b is Map && tStr(b['message']).isNotEmpty) message = tStr(b['message']);
    } on ApiException catch (e) {
      if (e.message.isNotEmpty) message = e.message;
    }
    if (!mounted) return;
    trackerToast(context, ok ? 'Payment confirmed' : 'Payment not confirmed yet', description: message, error: !ok);
    setState(() => _verifying = false);
    if (ok) _reload();
  }

  Future<void> _startCheckout() async {
    setState(() => _checkoutBusy = true);
    try {
      final base = '${Env.webBase}$billingReturnPath';
      Map res;
      try {
        final r = await _api.post('/api/PlatformBilling/checkout',
            body: {'userId': _userId, 'successUrl': '$base?billing=success', 'failureUrl': '$base?billing=cancel'});
        res = r is Map ? r : {};
      } on ApiException catch (e) {
        res = {'success': false, 'message': e.message.isNotEmpty ? e.message : 'Checkout failed (${e.statusCode})'};
      }
      if (res['success'] == false || tStr(res['checkoutUrl']).isEmpty) {
        if (mounted) trackerToast(context, 'Could not start checkout', description: tStr(res['message']), error: true);
        return;
      }
      if (!mounted) return;
      final back = await Navigator.of(context).push<Uri>(MaterialPageRoute(
        builder: (_) => _CheckoutScreen(url: tStr(res['checkoutUrl']), returnPath: billingReturnPath),
      ));
      if (back == null || !mounted) return;
      final status = back.queryParameters['billing'];
      final reference = back.queryParameters['reference'] ?? back.queryParameters['trxref'];
      if (status == 'success' && reference != null && reference.isNotEmpty) {
        _verify(reference);
      } else if (status == 'cancel') {
        trackerToast(context, 'Checkout cancelled', description: 'No changes were made.');
      }
    } finally {
      if (mounted) setState(() => _checkoutBusy = false);
    }
  }

  /// jpost: ok unless the call failed or answered ok:false.
  Future<({bool ok, String message})> _post(String path, Map<String, Object?> body) async {
    try {
      final r = await _api.post(path, body: body);
      final ok = !(r is Map && r['ok'] == false);
      final m = r is Map ? tStr(r['message']) : '';
      return (ok: ok, message: m.isNotEmpty ? m : 'Done.');
    } on ApiException catch (e) {
      return (ok: false, message: e.message.isNotEmpty ? e.message : 'Failed (${e.statusCode})');
    }
  }

  Future<void> _act(Future<({bool ok, String message})> Function() fn) async {
    final r = await fn();
    if (!mounted) return;
    trackerToast(context, r.ok ? 'Done' : 'Not changed', description: r.message, error: !r.ok);
    if (r.ok) _reload();
  }

  Future<({bool ok, String message})> _cancelMarketChange() async {
    try {
      final r = await _api.delete('/api/PlatformBilling/market-change?userId=${Uri.encodeQueryComponent(_userId)}');
      return (ok: true, message: r is Map ? tStr(r['message']) : '');
    } on ApiException catch (e) {
      return (ok: false, message: e.message);
    }
  }

  Future<void> _explain(String farmId) async {
    try {
      final e = await _api.get('/api/PlatformBilling/explain', query: {..._q, 'farmId': farmId});
      if (!mounted || e is! Map) return;
      showDialog<void>(context: context, builder: (_) => _ExplainDialog(e));
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'No pricing details yet', description: e.message.isEmpty ? null : e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: billingReturnPath);
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Subscription & Billing')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 28), children: [
          const Text('Subscription & Billing', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
          const Text('One consolidated VisibilityCore subscription across every company in your organization.',
              style: TextStyle(fontSize: 14, color: TColors.slate600)),
          const SizedBox(height: 16),
          ..._body(),
        ]),
      ),
    );
  }

  List<Widget> _body() {
    if (_loading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 64),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Loading your billing…', style: TextStyle(color: TColors.slate600)),
          ]),
        ),
      ];
    }
    final s = _summary;
    if (_loadError.isNotEmpty || s == null) return [TrackerBanner.error(_loadError.isNotEmpty ? _loadError : 'Could not load billing.')];
    final acct = (s['account'] as Map?) ?? {};
    final preview = (s['preview'] as Map?) ?? {};
    final companies = [for (final c in (s['companies'] as List? ?? const [])) if (c is Map) c];
    final pending = [for (final p in (s['pendingTierChanges'] as List? ?? const [])) if (p is Map) p];
    final status = tStr(acct['status']);
    final trialEnded = status == 'Trial' && tNum(acct['trialDaysLeft']) <= 0;
    final canPay = !tBool(preview['hasUnpricedCompanies']) && tNum(preview['total']) > 0;
    final cur = preview['currencyCode'];
    final annual = tStr(acct['billingCycle']) == 'annual';
    const strong = TextStyle(fontWeight: FontWeight.w700);
    Widget link(String t, VoidCallback onTap, {Color color = const Color(0xFF4F46E5)}) =>
        InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(t, style: TextStyle(fontSize: 14, color: color))));
    Widget totalRow(String l, String v, {Color? color, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(l, style: TextStyle(fontSize: bold ? 16 : 14, fontWeight: bold ? FontWeight.w600 : null, color: color ?? (bold ? TColors.slate900 : TColors.slate600)))),
            Text(v, style: TextStyle(fontSize: bold ? 16 : 14, fontWeight: bold ? FontWeight.w600 : null, color: color ?? (bold ? TColors.slate900 : TColors.slate600))),
          ]),
        );

    return [
      if (pending.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: const Color(0x99EEF2FF), border: Border.all(color: const Color(0xFFC7D2FE)), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final p in pending)
              Text.rich(TextSpan(children: [
                TextSpan(text: tStr(p['companyName']), style: strong),
                const TextSpan(text: ' now qualifies for '),
                TextSpan(text: tStr(p['toTierName']), style: strong),
                TextSpan(text: ' — its plan changes from ${tStr(p['fromTierName'])} on ${_date(p['effectiveDate'])}. Nothing changes mid-period.'),
              ]), style: const TextStyle(fontSize: 14, color: Color(0xFF312E81))),
          ]),
        ),
      if (tStr(acct['pendingMarketCode']).isNotEmpty)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
          child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Billing market changes to '),
              TextSpan(text: tStr(acct['pendingMarketCode']), style: strong),
              TextSpan(text: ' on ${acct['pendingMarketEffective'] != null ? _date(acct['pendingMarketEffective']) : 'next cycle'}.'),
            ]), style: const TextStyle(fontSize: 14, color: TColors.slate700)),
            TextButton(onPressed: () => _act(_cancelMarketChange), child: const Text('Undo')),
          ]),
        ),
      if (tBool(acct['cancelAtPeriodEnd']))
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: const Color(0x99FEF2F2), border: Border.all(color: TColors.red200), borderRadius: BorderRadius.circular(8)),
          child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: [
            Text(
                'Your subscription will not renew. Full access continues through ${acct['currentPeriodEnd'] != null ? _date(acct['currentPeriodEnd']) : 'the period end'}.',
                style: const TextStyle(fontSize: 14, color: Color(0xFF7F1D1D))),
            OutlinedButton(onPressed: () => _act(() => _post('/api/PlatformBilling/reactivate', {'userId': _userId})), child: const Text('Reactivate')),
          ]),
        ),
      TCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('VisibilityCore subscription', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate500)),
                billingStatusBadge(trialEnded ? 'Trial ended' : status),
              ]),
              const SizedBox(height: 6),
              Text.rich(TextSpan(children: [
                TextSpan(text: '${tStr(acct['marketCode'])} · ${tStr(acct['currencyCode'])}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900)),
                TextSpan(text: '  billed ${tStr(acct['billingCycle'])}', style: const TextStyle(fontSize: 14, color: TColors.slate500)),
              ])),
              if (status == 'Trial' && !trialEnded)
                Text('${_thousands(acct['trialDaysLeft'])} trial days remaining', style: const TextStyle(fontSize: 14, color: TColors.slate500)),
              const SizedBox(height: 12),
              Wrap(spacing: 16, runSpacing: 2, children: [
                link('Switch to ${annual ? 'monthly' : 'annual'} billing',
                    () => _act(() => _post('/api/PlatformBilling/billing-cycle', {'userId': _userId, 'cycle': annual ? 'monthly' : 'annual'}))),
                link('Change billing market', _openMarket),
                if (!tBool(acct['cancelAtPeriodEnd']))
                  link('Cancel subscription', () => _act(() => _post('/api/PlatformBilling/cancel', {'userId': _userId, 'reason': null})), color: TColors.slate400),
              ]),
            ]),
          ),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(color: Color(0xB3F8FAFC), border: Border(top: BorderSide(color: TColors.slate100))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Next bill', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate500)),
              Text(billingMoney(preview['total'], cur), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: TColors.slate900)),
              Text.rich(TextSpan(children: [
                TextSpan(text: '${_date(preview['periodStart'])} – ${_date(preview['periodEnd'])}'),
                if (tNum(preview['discountAmount']) > 0)
                  TextSpan(text: ' · includes ${_thousands(preview['discountPercent'])}% discount', style: const TextStyle(color: Color(0xFF16A34A))),
              ]), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _checkoutBusy || _verifying || !canPay ? null : _startCheckout,
                icon: _checkoutBusy || _verifying
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.credit_card, size: 16),
                label: Text(_verifying ? 'Confirming payment…' : 'Pay this period'),
              ),
              if (tBool(preview['hasUnpricedCompanies']))
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Checkout opens once pricing is configured for all your business types.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      TCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(Icons.business_outlined, size: 16, color: TColors.slate400),
              const SizedBox(width: 6),
              const Expanded(child: Text('Companies on this bill', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
              Text('${_thousands(preview['eligibleCompanyCount'])} of ${companies.length} billed', style: const TextStyle(fontSize: 14, color: TColors.slate500)),
            ]),
          ),
          const Divider(height: 1, color: TColors.slate100),
          for (final c in companies) ...[_companyRow(c), const Divider(height: 1, color: TColors.slate100)],
          Container(
            color: const Color(0xB3F8FAFC),
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              totalRow('Subtotal', billingMoney(preview['subtotal'], cur)),
              if (tNum(preview['discountAmount']) > 0)
                totalRow('Multi-company discount (${_thousands(preview['discountPercent'])}%)', '-${billingMoney(preview['discountAmount'], cur)}',
                    color: const Color(0xFF15803D)),
              if (tNum(preview['taxAmount']) > 0) totalRow('Tax', billingMoney(preview['taxAmount'], cur)),
              const Divider(height: 10),
              totalRow('Total / month', billingMoney(preview['total'], cur), bold: true),
              if (tBool(preview['hasUnpricedCompanies']))
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                      'Pricing for some business types is being finalized. Those companies are listed but not charged; contact VisibilityCore support to enable them.',
                      style: TextStyle(fontSize: 12, color: TColors.slate500)),
                ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<int>(
            segments: const [ButtonSegment(value: 0, label: Text('Invoices')), ButtonSegment(value: 1, label: Text('Payments'))],
            selected: {_tab},
            onSelectionChanged: (v) => setState(() => _tab = v.first),
          ),
          const SizedBox(height: 10),
          if (_tab == 0)
            _invoices.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No invoices yet — your first invoice is created when you pay.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: TColors.slate500)),
                  )
                : TrackerTable(
                    columns: const [TCol('Invoice', width: 130), TCol('Period', width: 170), TCol('Amount', right: true, width: 120), TCol('Balance', right: true, width: 120), TCol('Status', width: 100)],
                    rows: [
                      for (final i in _invoices)
                        [
                          Text(tStr(i['invoiceNumber']), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                          cellText('${_date(i['periodStart'])} – ${_date(i['periodEnd'])}', color: TColors.slate600),
                          cellText(billingMoney(i['totalAmount'], i['currencyCode'])),
                          cellText(billingMoney(i['balance'], i['currencyCode'])),
                          Align(alignment: Alignment.centerLeft, child: billingStatusBadge(tStr(i['status']))),
                        ],
                    ],
                  )
          else
            _payments.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No payments yet.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: TColors.slate500)),
                  )
                : TrackerTable(
                    columns: const [TCol('Date', width: 170), TCol('Provider', width: 100), TCol('Amount', right: true, width: 120), TCol('Invoice', width: 130), TCol('Status', width: 100)],
                    rows: [
                      for (final p in _payments)
                        [
                          cellText(p['paymentDateUtc'] != null ? _dateTime(p['paymentDateUtc']) : '—', color: TColors.slate600),
                          cellText(_cap(tStr(p['provider']))),
                          cellText(billingMoney(p['amount'], p['currencyCode'])),
                          Text(tStr(p['invoiceNumber']).isNotEmpty ? tStr(p['invoiceNumber']) : '—', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                          Align(alignment: Alignment.centerLeft, child: billingStatusBadge(tStr(p['status']))),
                        ],
                    ],
                  ),
        ]),
      ),
    ];
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _companyRow(Map c) {
    final unpriced = tStr(c['pricingStatus']) == 'PricingNotConfigured';
    final evaluation = tStr(c['pricingStatus']) == 'Evaluation';
    final participation = tStr(c['participationStatus']);
    final inactive = participation != 'Active' && participation != 'EnterpriseContract';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tStr(c['companyName']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
            Text(tStr(c['businessType']), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            const SizedBox(height: 4),
            inactive ? billingStatusBadge(participation) : tierBadge(c['tierName']),
          ]),
        ),
        const SizedBox(width: 8),
        if (unpriced)
          const TBadge('Pricing pending', bg: TColors.amber50, fg: Color(0xFF92400E))
        else if (evaluation)
          Text('Free until ${c['evaluationUntilUtc'] != null ? _date(c['evaluationUntilUtc']) : 'review'}', style: const TextStyle(fontSize: 12, color: TColors.slate500))
        else if (inactive)
          const Text('—', style: TextStyle(color: TColors.slate400))
        else
          Text.rich(TextSpan(children: [
            TextSpan(text: billingMoney(c['monthlyAmount'], c['currencyCode']), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
            const TextSpan(text: '/mo', style: TextStyle(fontSize: 12, color: TColors.slate400)),
          ])),
        IconButton(
          tooltip: 'Why this price?',
          icon: const Icon(Icons.info_outline, size: 18, color: TColors.slate400),
          onPressed: () => _explain(tStr(c['farmId'])),
        ),
      ]),
    );
  }

  Future<void> _openMarket() async {
    final acct = (_summary?['account'] as Map?) ?? {};
    final preview = (_summary?['preview'] as Map?) ?? {};
    await showDialog<void>(
      context: context,
      builder: (_) => _MarketDialog(
        api: _api,
        userId: _userId,
        currentMarket: tStr(acct['marketCode']),
        currentPreview: preview,
        onDone: (r) {
          if (!mounted) return;
          trackerToast(context, r.ok ? 'Done' : 'Not changed', description: r.message, error: !r.ok);
          if (r.ok) _reload();
        },
        post: _post,
      ),
    );
  }
}

/// "Change billing market": request, the shown price impact, confirmation.
class _MarketDialog extends StatefulWidget {
  const _MarketDialog({required this.api, required this.userId, required this.currentMarket, required this.currentPreview, required this.onDone, required this.post});
  final ApiClient api;
  final String userId, currentMarket;
  final Map currentPreview;
  final void Function(({bool ok, String message})) onDone;
  final Future<({bool ok, String message})> Function(String, Map<String, Object?>) post;
  @override
  State<_MarketDialog> createState() => _MarketDialogState();
}

class _MarketDialogState extends State<_MarketDialog> {
  String _target = 'NG';
  Map? _preview;
  bool _busy = false;
  final _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load(_target);
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load(String code) async {
    setState(() {
      _target = code;
      _preview = null;
    });
    try {
      final r = await widget.api.get('/api/PlatformBilling/market-preview', query: {'userId': widget.userId, 'marketCode': code});
      if (mounted && code == _target) setState(() => _preview = r is Map ? r : null);
    } on ApiException {
      if (mounted) setState(() => _preview = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    final inner = (p?['preview'] as Map?) ?? {};
    return AlertDialog(
      title: const Text('Change billing market'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Takes effect at your next billing cycle — current invoices and the running period never change.',
              style: TextStyle(fontSize: 14, color: TColors.slate500)),
          const SizedBox(height: 12),
          AppSelect<String>(
            value: _target,
            hintText: 'New market',
            items: const [
              AppSelectItem(value: 'GH', label: 'Ghana — GHS'),
              AppSelectItem(value: 'NG', label: 'Nigeria — NGN'),
              AppSelectItem(value: 'US', label: 'United States — USD'),
            ],
            onChanged: (v) {
              if (v != null) _load(v);
            },
          ),
          if (p != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xB3F8FAFC), border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
              child: p['marketActive'] != true
                  ? Text('${tStr(p['marketName'])} is not open yet — the request will be declined until VisibilityCore launches there.',
                      style: const TextStyle(fontSize: 14, color: Color(0xFF92400E)))
                  : inner['hasUnpricedCompanies'] == true
                      ? Text('Pricing for some of your business types is not configured in ${tStr(p['marketName'])} yet.',
                          style: const TextStyle(fontSize: 14, color: Color(0xFF92400E)))
                      : Text.rich(TextSpan(children: [
                          const TextSpan(text: 'Estimated new total: '),
                          TextSpan(text: '${tStr(inner['currencyCode'])} ${_thousands(inner['total'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          const TextSpan(text: ' /month '),
                          TextSpan(
                              text: '(currently ${tStr(widget.currentPreview['currencyCode'])} ${_thousands(widget.currentPreview['total'])})',
                              style: const TextStyle(color: TColors.slate500)),
                        ]), style: const TextStyle(fontSize: 14)),
            ),
          ],
          const SizedBox(height: 10),
          AppInput(controller: _reason, hintText: 'Reason (e.g. business relocated)'),
        ]),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(
          onPressed: _busy || _target == widget.currentMarket
              ? null
              : () async {
                  setState(() => _busy = true);
                  final r = await widget.post('/api/PlatformBilling/market-change', {'userId': widget.userId, 'marketCode': _target, 'reason': _reason.text});
                  widget.onDone(r);
                  if (context.mounted) Navigator.pop(context);
                },
          child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Confirm request'),
        ),
      ],
    );
  }
}

/// "How this plan is calculated", read from the stored evaluation.
class _ExplainDialog extends StatelessWidget {
  const _ExplainDialog(this.e);
  final Map e;
  @override
  Widget build(BuildContext context) {
    final rows = <(String, Widget)>[
      ('Billing profile', Text(tStr(e['billingProfileName']))),
      ('Current usage', Text(_thousands(e['metricValue']))),
      ('Plan', Align(alignment: Alignment.centerLeft, child: tierBadge(e['tierName']))),
      ('Billing market', Text(tStr(e['marketName']))),
      ('Price', Text(tStr(e['pricingStatus']) == 'PricingNotConfigured' ? 'Being finalized' : '${billingMoney(e['monthlyAmount'], e['currencyCode'])}/month')),
      if (tStr(e['nextTierName']).isNotEmpty && e['nextTierAtValue'] != null)
        ('Next plan', Text('${tStr(e['nextTierName'])} at ${_thousands(e['nextTierAtValue'])}')),
    ];
    return AlertDialog(
      title: const Text('How this plan is calculated'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tStr(e['companyName']), style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
        const SizedBox(height: 8),
        for (final (l, w) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(l, style: const TextStyle(fontSize: 14, color: TColors.slate500))),
              Expanded(child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 14, color: TColors.slate700), child: w)),
            ]),
          ),
        const SizedBox(height: 6),
        Text('Evaluated ${_dateTime(e['evaluatedAtUtc'])}. Your price only changes at the start of a billing cycle — never mid-period.',
            style: const TextStyle(fontSize: 12, color: TColors.slate500)),
      ]),
    );
  }
}

/// The payment provider's checkout, in-app. Leaving for the return path
/// closes it and hands back the return URL.
class _CheckoutScreen extends StatefulWidget {
  const _CheckoutScreen({required this.url, required this.returnPath});
  final String url, returnPath;
  @override
  State<_CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<_CheckoutScreen> {
  late final WebViewController _c = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: (req) {
      final u = Uri.tryParse(req.url);
      if (u != null && u.path == widget.returnPath && u.queryParameters.containsKey('billing')) {
        Navigator.of(context).pop(u);
        return NavigationDecision.prevent;
      }
      return NavigationDecision.navigate;
    }))
    ..loadRequest(Uri.parse(widget.url));

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Checkout')), body: WebViewWidget(controller: _c));
}
