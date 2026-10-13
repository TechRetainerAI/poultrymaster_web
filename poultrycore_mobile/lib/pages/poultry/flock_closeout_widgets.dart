// The Flock Closeout dialogs and the lifetime view, as
// components/poultry/flock-closeout-wizard.tsx, flock-lifetime-dialog.tsx and
// flock-lifetime-view.tsx (migrations 338/339).

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../shared/business_dates.dart';
import 'flock_closeout_logic.dart';
import 'reports/report_format.dart';
import 'trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, jsNum;
import 'trackers/tracker_widgets.dart';

/// REST client for FlockCloseoutController. farmId rides in the query on every
/// call, writes included: that is where the API's IAM filter reads it from.
class FlockCloseoutApi {
  FlockCloseoutApi(this.session, this.company);
  final Session session;
  final Company company;
  ApiClient get _api => session.farmClient;
  String get farmId => company.farmId;
  String get userId => session.tokens.userId ?? '';

  Future<Object?> lifetime({int? flockId}) =>
      _api.get('/api/flock-closeout/lifetime', query: {'farmId': farmId, if (flockId != null) 'flockId': '$flockId'});
  Future<Object?> context(int flockId) =>
      _api.get('/api/flock-closeout/$flockId/context', query: {'userId': userId, 'farmId': farmId});
  Future<Object?> history(int flockId) => _api.get('/api/flock-closeout/$flockId/history', query: {'farmId': farmId});
  Future<Object?> close(int flockId, Map<String, dynamic> body) =>
      _api.post('/api/flock-closeout/$flockId', query: {'farmId': farmId}, body: body);
  Future<Object?> reopen(int flockId, String reason, bool reverseSales) => _api.post('/api/flock-closeout/$flockId/reverse',
      query: {'farmId': farmId}, body: {'userId': userId, 'farmId': farmId, 'reason': reason, 'reverseSales': reverseSales});
}

String _n(num? v) => v == null ? '—' : fmtNum(v, 3);
String _pct(Object? v) => v == null ? '—' : '${(tNum(v) * 100).toStringAsFixed(2)}%';
String _day(Object? v) {
  final s = tStr(v);
  return s.isEmpty ? '—' : (s.length >= 10 ? s.substring(0, 10) : s);
}

const _orange600 = Color(0xFFEA580C);
const _orange50 = Color(0xFFFFF7ED);
const _sky50 = Color(0xFFF0F9FF);
const _sky600 = Color(0xFF0284C7);
const _blue50 = Color(0xFFEFF6FF);
const _blue900 = Color(0xFF1E3A8A);
const _violet700 = Color(0xFF6D28D9);

/// The web Alert: an icon and a message in a tinted box.
Widget closeoutAlert(String text, {required String tone, Widget? child}) {
  final (bg, border, fg, icon, iconColor) = switch (tone) {
    'ok' => (TColors.emerald50, TColors.emerald200, TColors.emerald900, Icons.check_circle_outline, TColors.emerald600),
    'warn' => (TColors.amber50, TColors.amber200, TColors.amber900, Icons.error_outline, TColors.amber600),
    _ => (TColors.red50, TColors.red200, TColors.red700, Icons.error_outline, TColors.red600),
  };
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 16, color: iconColor),
      const SizedBox(width: 10),
      Expanded(child: child ?? Text(text, style: TextStyle(fontSize: 13, color: fg))),
    ]),
  );
}

Widget _sectionLabel(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text.toUpperCase(),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .5, color: TColors.slate500)),
    );

Widget _label(String text, Widget field) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.slate700)),
      const SizedBox(height: 4),
      field,
    ]);

/// Two fields side by side.
Widget _pair(Widget a, Widget b) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: a),
      const SizedBox(width: 12),
      Expanded(child: b),
    ]);

num? _parse(String s) => s.trim().isEmpty ? null : num.tryParse(s.trim());

// ===========================================================================
// Close Flock wizard
// ===========================================================================

/// Opens the Close Flock wizard. [onClosed] runs the moment the close
/// succeeds, while the result is still showing.
Future<void> showFlockCloseoutWizard(BuildContext context,
    {required Session session, required Company company, required int flockId, VoidCallback? onClosed}) {
  return showDialog<void>(
    context: context,
    builder: (_) => FlockCloseoutWizard(session: session, company: company, flockId: flockId, onClosed: onClosed),
  );
}

class FlockCloseoutWizard extends StatefulWidget {
  const FlockCloseoutWizard({super.key, required this.session, required this.company, required this.flockId, this.onClosed});
  final Session session;
  final Company company;
  final int flockId;
  final VoidCallback? onClosed;

  @override
  State<FlockCloseoutWizard> createState() => _FlockCloseoutWizardState();
}

class _FlockCloseoutWizardState extends State<FlockCloseoutWizard> {
  late final _api = FlockCloseoutApi(widget.session, widget.company);
  int _step = 0;
  bool _loading = true;
  String _loadError = '';
  Map? _context;
  List<Map> _customers = [];
  List<Map> _cash = [];
  String _reasonChoice = closeoutReasons.first;
  CloseoutDraft _draft = CloseoutDraft();
  bool _submitting = false;
  List<String> _serverErrors = [];
  Map? _result;
  final _otherReason = TextEditingController();
  final _notes = TextEditingController();
  FarmMoney _money = const FarmMoney();

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    _load();
  }

  @override
  void dispose() {
    _otherReason.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    Future<Object?> soft(Future<Object?> f) async {
      try {
        return await f;
      } on ApiException {
        return const [];
      }
    }

    Object? ctx;
    String? err;
    final api = widget.session.farmClient;
    final uq = {'userId': _api.userId, 'farmId': _api.farmId};
    final results = await Future.wait([
      _api.context(widget.flockId).then<Object?>((v) => v, onError: (Object e) {
        err = e is ApiException ? e.message : '$e';
        return null;
      }),
      soft(api.get('/api/Customer', query: uq)),
      soft(api.get('/api/Poultry/cash-accounts', query: {'farmId': _api.farmId})),
    ]);
    if (!mounted) return;
    ctx = results[0];
    setState(() {
      if (ctx is! Map) {
        _loadError = (err ?? '').isNotEmpty ? err! : "Could not load this flock's bird position.";
      } else {
        _context = ctx;
        _reasonChoice = closeoutReasons.first;
        _draft = CloseoutDraft(closedDate: _day(_context!['businessDate']) == '—' ? '' : _day(_context!['businessDate']));
      }
      _customers = rowsOf(results[1]);
      _cash = [for (final a in rowsOf(results[2])) if (a['isActive'] == true) a];
      _loading = false;
    });
  }

  int? get _defaultAccountId {
    if (_cash.isEmpty) return null;
    final main = _cash.where((a) => tStr(a['accountName']).trim().toLowerCase() == 'main cash account');
    return tIntOrNull((main.isNotEmpty ? main.first : _cash.first)['poultryCashAccountId']);
  }

  Map get _position => _context?['position'] is Map ? _context!['position'] as Map : const {};
  int get _live => tNum(_position['currentLiveBirds']).toInt();

  void _changed() => setState(() {});

  Future<void> _submit() async {
    final ctx = _context;
    if (ctx == null) return;
    setState(() {
      _submitting = true;
      _serverErrors = [];
    });
    final d = _draft;
    final body = <String, dynamic>{
      'userId': _api.userId,
      'farmId': _api.farmId,
      'closedDate': d.closedDate,
      'reason': d.reason.trim(),
      'notes': d.notes.trim().isEmpty ? null : d.notes.trim(),
      'sales': [
        for (final s in d.sales)
          () {
            final name = s.customerName.trim();
            final match = _customers.where((c) => tStr(c['name']).trim().toLowerCase() == name.toLowerCase());
            return {
              'quantity': s.quantity,
              'unitPrice': s.unitPrice,
              'totalAmount': saleTotal(s),
              'customerId': match.isNotEmpty ? tIntOrNull(match.first['customerId']) : null,
              'customerName': name.isEmpty ? null : name,
              'paymentTerms': s.paymentTerms,
              'amountPaid': s.paymentTerms == 'PartPaid' ? (s.amountPaid ?? 0) : null,
              'paymentMethod': s.paymentTerms == 'Credit' ? null : s.paymentMethod,
              'poultryCashAccountId': s.paymentTerms == 'Credit' ? null : s.cashAccountId,
            };
          }(),
      ],
      'culls': [for (final c in d.culls) {'quantity': c.quantity, 'notes': c.notes}],
      'transfers': [for (final t in d.transfers) {'quantity': t.quantity, 'destination': t.destination}],
    };
    Map? res;
    String message = '';
    try {
      final r = await _api.close(widget.flockId, body);
      res = r is Map ? r : null;
    } on ApiException catch (e) {
      res = e.body is Map ? e.body as Map : null;
      message = e.message;
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (res != null && res['success'] == true) {
        _result = res;
      } else {
        final errs = res?['errors'] is List ? [for (final e in res!['errors'] as List) tStr(e)] : <String>[];
        _serverErrors = errs.isNotEmpty
            ? errs
            : [tStr(res?['message']).isNotEmpty ? tStr(res?['message']) : (message.isNotEmpty ? message : 'The flock could not be closed.')];
      }
    });
    if (_result != null) widget.onClosed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final ctx = _context;
    final name = tStr(ctx?['flock'] is Map ? (ctx!['flock'] as Map)['name'] : null);
    return PopScope(
      canPop: !_submitting,
      child: AlertDialog(
        scrollable: true,
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        title: Row(children: [
          const Icon(Icons.flag_outlined, size: 20, color: TColors.slate600),
          const SizedBox(width: 8),
          Expanded(child: Text('Close ${name.isEmpty ? 'flock' : name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
        ]),
        content: SizedBox(
          width: 640,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              "End this flock's life: account for every bird still standing, then close it and free its house. The flock and its history are kept — nothing is deleted.",
              style: TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text("Reconciling the flock's birds…", style: TextStyle(color: TColors.slate500)),
                ]),
              )
            else if (_loadError.isNotEmpty)
              closeoutAlert(_loadError, tone: 'error')
            else if (ctx != null && _result != null)
              _resultView(_result!)
            else if (ctx != null)
              _wizard(ctx),
          ]),
        ),
      ),
    );
  }

  Widget _resultView(Map r) {
    final saleIds = r['saleIds'] is List ? r['saleIds'] as List : const [];
    final warnings = r['warnings'] is List ? r['warnings'] as List : const [];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      closeoutAlert(tStr(r['message']), tone: 'ok'),
      if (saleIds.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          '${saleIds.length == 1 ? 'The sale is' : '${saleIds.length} sales are'} on the Sales page (${saleIds.map((id) => '#$id').join(', ')}), with any balance owed on the customer\'s account.',
          style: const TextStyle(fontSize: 13, color: TColors.slate600),
        ),
      ],
      for (final w in warnings) ...[const SizedBox(height: 12), closeoutAlert(tStr(w), tone: 'warn')],
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ),
    ]);
  }

  Widget _wizard(Map ctx) {
    final errors = validateCloseoutDraft(_draft, ctx);
    final remaining = unresolvedBirds(_position, _draft);
    final blocked = ctx['isClosed'] == true || tStr(ctx['ineligibleReason']).isNotEmpty;
    final shown = {...(_step == 2 ? [...errors, ..._serverErrors] : _serverErrors)}.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _stepBar(),
      const SizedBox(height: 16),
      if (blocked) ...[
        closeoutAlert(ctx['isClosed'] == true ? 'This flock is already closed.' : tStr(ctx['ineligibleReason']), tone: 'error'),
        const SizedBox(height: 16),
      ],
      if (_step == 0) _reconcile(ctx),
      if (_step == 1) _dispose(ctx, remaining),
      if (_step == 2) _close(ctx),
      if (shown.isNotEmpty) ...[
        const SizedBox(height: 16),
        closeoutAlert('',
            tone: 'error',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final e in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('•  $e', style: const TextStyle(fontSize: 13, color: TColors.red700)),
                ),
            ])),
      ],
      const SizedBox(height: 16),
      Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
        if (_step > 0)
          OutlinedButton.icon(
            onPressed: _submitting ? null : () => setState(() => _step -= 1),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Back'),
          ),
        if (_step < 2)
          FilledButton.icon(
            onPressed: blocked || _live < 0 || (_step == 1 && remaining != 0) ? null : () => setState(() => _step += 1),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('Next'),
          ),
        if (_step == 2)
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: TColors.slate900, foregroundColor: Colors.white),
            onPressed: _submitting || errors.isNotEmpty ? null : _submit,
            icon: _submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.flag_outlined, size: 16),
            label: Text(_draft.sales.isNotEmpty ? 'Close flock & record sales' : 'Close flock'),
          ),
      ]),
      if (_step == 1 && remaining != 0) ...[
        const SizedBox(height: 6),
        Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
          TBadge(remaining > 0 ? _n(remaining) : '−${_n(-remaining)}', bg: Colors.white, fg: TColors.slate900, border: TColors.slate300),
          const Text('Every bird must be accounted for before you continue.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
        ]),
      ],
    ]);
  }

  Widget _stepBar() => Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (var i = 0; i < closeoutSteps.length; i++)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == _step ? TColors.slate900 : (i < _step ? TColors.emerald50 : null),
                border: Border.all(color: i == _step ? TColors.slate900 : (i < _step ? TColors.emerald500 : TColors.slate300)),
              ),
              child: Text('${i + 1}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: i == _step ? Colors.white : (i < _step ? TColors.emerald700 : TColors.slate500))),
            ),
            const SizedBox(width: 6),
            Text(closeoutSteps[i],
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: i == _step ? FontWeight.w600 : FontWeight.w400,
                    color: i == _step ? TColors.slate900 : TColors.slate500)),
            if (i < closeoutSteps.length - 1) ...[
              const SizedBox(width: 6),
              Container(width: 18, height: 1, color: TColors.slate300),
            ],
          ]),
      ]);

  // ---------------------------------------------------------- step 1

  Widget _reconcile(Map ctx) {
    final lines = reconciliationLines(_position);
    final live = _live;
    final lastCountDate = tStr(_position['lastCountDate']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sectionLabel('Where the birds went'),
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
        child: Column(children: [
          for (var i = 0; i < lines.length; i++)
            Builder(builder: (_) {
              final l = lines[i];
              final strong = l.sign == '=';
              final isLive = l.key == 'live';
              final color = isLive ? _blue900 : (l.muted ? TColors.slate500 : TColors.slate900);
              final prefix = switch (l.sign) {
                '=' => '',
                '±' => l.value >= 0 ? '+ ' : '− ',
                '-' => '− ',
                _ => '+ ',
              };
              return Container(
                decoration: BoxDecoration(
                  color: isLive ? _blue50 : (strong ? TColors.slate50 : null),
                  border: i == 0 ? null : const Border(top: BorderSide(color: TColors.slate200)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.label, style: TextStyle(fontSize: 13, fontWeight: strong ? FontWeight.w600 : FontWeight.w400, color: color)),
                      if (l.hint != null) Text(l.hint!, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                      if (l.key == 'lastCount' && lastCountDate.isNotEmpty)
                        Text('Latest production record, ${_day(lastCountDate)}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Text('$prefix${_n(l.sign == '±' ? l.value.abs() : l.value)}',
                      style: TextStyle(fontSize: 13, fontWeight: strong ? FontWeight.w600 : FontWeight.w400, color: color)),
                ]),
              );
            }),
        ]),
      ),
      const SizedBox(height: 12),
      if (live < 0)
        closeoutAlert(
            'The records account for ${_n(-live)} more birds than this flock had. That usually means a bird sale was also deducted by hand on a production record. Correct that record before closing.',
            tone: 'error')
      else
        Text(
          '${live == 0 ? 'No birds are left standing, so this flock can be closed without selling, culling or transferring any.' : '${_n(live)} birds are still standing. The next step accounts for every one of them.'}'
          ' If a physical count differs, record the missing birds as mortality on a production record first — closing a flock never invents deaths to make the numbers fit.',
          style: const TextStyle(fontSize: 13, color: TColors.slate600),
        ),
    ]);
  }

  // ---------------------------------------------------------- step 2

  Widget _addButton(String label, VoidCallback onTap) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
        onPressed: onTap,
        icon: const Icon(Icons.add, size: 16),
        label: Text(label),
      );

  Widget _dispose(Map ctx, int remaining) {
    final totals = dispositionTotals(_draft);
    final (bg, border, fg) = remaining == 0
        ? (TColors.emerald50, TColors.emerald200, TColors.emerald900)
        : remaining > 0
            ? (TColors.amber50, TColors.amber200, TColors.amber900)
            : (TColors.rose50, TColors.rose200, const Color(0xFF881337));
    int left() {
      final l = unresolvedBirds(_position, _draft);
      return l < 0 ? 0 : l;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(6)),
        child: Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, runSpacing: 2, children: [
          Text('${_n(_live)} standing · ${_n(totals.total)} accounted for', style: TextStyle(fontSize: 13, color: fg)),
          Text(
            remaining == 0 ? 'Balanced' : (remaining > 0 ? '${_n(remaining)} still to account for' : '${_n(-remaining)} too many'),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      // Sales
      Row(children: [
        Expanded(child: _sectionLabel('Sold')),
        _addButton('Sale', () => setState(() => _draft.sales.add(CloseoutSale(quantity: left(), cashAccountId: _defaultAccountId)))),
      ]),
      Text.rich(
        TextSpan(children: [
          TextSpan(
              text:
                  'Spent-layer sales are recorded as ordinary ${tStr(ctx['birdProductName'])} sales. There is no separate save: each sale here is saved together with the closeout when you press '),
          const TextSpan(text: 'Close flock & record sales', style: TextStyle(fontWeight: FontWeight.w500, color: TColors.slate700)),
          const TextSpan(text: ' on the last step, so a sale can never be left behind on a flock that did not close.'),
        ]),
        style: const TextStyle(fontSize: 12, color: TColors.slate500),
      ),
      for (var i = 0; i < _draft.sales.length; i++) ...[
        const SizedBox(height: 8),
        _SaleCard(
          key: ObjectKey(_draft.sales[i]),
          index: i,
          sale: _draft.sales[i],
          customers: [for (final c in _customers) tStr(c['name'])],
          cash: _cash,
          onChanged: _changed,
          onRemove: () => setState(() => _draft.sales.removeAt(i)),
        ),
      ],
      const SizedBox(height: 16),
      // Culls
      Row(children: [
        Expanded(child: _sectionLabel('Culled')),
        _addButton('Cull', () => setState(() => _draft.culls.add(CloseoutCull(quantity: left())))),
      ]),
      for (var i = 0; i < _draft.culls.length; i++) ...[
        const SizedBox(height: 8),
        _LineRow(
          key: ObjectKey(_draft.culls[i]),
          quantity: _draft.culls[i].quantity,
          textLabel: 'Notes',
          textHint: 'e.g. culled and disposed on site',
          text: _draft.culls[i].notes,
          onQuantity: (v) => setState(() => _draft.culls[i].quantity = v),
          onText: (v) => setState(() => _draft.culls[i].notes = v),
          onRemove: () => setState(() => _draft.culls.removeAt(i)),
        ),
      ],
      const SizedBox(height: 16),
      // Transfers
      Row(children: [
        Expanded(child: _sectionLabel('Transferred off the farm')),
        _addButton('Transfer', () => setState(() => _draft.transfers.add(CloseoutTransfer(quantity: left())))),
      ]),
      if (_draft.transfers.isEmpty)
        const Text(
          'For birds leaving the company. Birds moving to another house stay the same flock — edit its house instead of closing it.',
          style: TextStyle(fontSize: 12, color: TColors.slate500),
        ),
      for (var i = 0; i < _draft.transfers.length; i++) ...[
        const SizedBox(height: 8),
        _LineRow(
          key: ObjectKey(_draft.transfers[i]),
          quantity: _draft.transfers[i].quantity,
          textLabel: 'Destination',
          textHint: 'Where did they go?',
          text: _draft.transfers[i].destination,
          onQuantity: (v) => setState(() => _draft.transfers[i].quantity = v),
          onText: (v) => setState(() => _draft.transfers[i].destination = v),
          onRemove: () => setState(() => _draft.transfers.removeAt(i)),
        ),
      ],
    ]);
  }

  // ---------------------------------------------------------- step 3

  Widget _figure(String label, String value, Color tone) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: tone)),
        ]),
      );

  Widget _close(Map ctx) {
    final totals = dispositionTotals(_draft);
    final earliest = DateTime.tryParse(_day(ctx['earliestCloseDate']));
    final latest = DateTime.tryParse(_day(ctx['businessDate']));
    final house = tStr(ctx['houseName']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _pair(
        _label(
          'Closing date',
          AppDateField(
            value: DateTime.tryParse(_draft.closedDate),
            firstDate: earliest,
            lastDate: latest,
            onChanged: (d) => setState(() => _draft.closedDate = d == null ? '' : isoDay(d)),
          ),
        ),
        _label(
          'Reason',
          AppSelect<String>(
            value: _reasonChoice,
            items: [for (final r in closeoutReasons) AppSelectItem(value: r, label: r)],
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _reasonChoice = v;
                _draft.reason = v == 'Other' ? '' : v;
                _otherReason.text = '';
              });
            },
          ),
        ),
      ),
      if (_reasonChoice == 'Other') ...[
        const SizedBox(height: 12),
        AppInput(
          controller: _otherReason,
          hintText: 'Why is this flock closing?',
          onChanged: (v) => setState(() => _draft.reason = v),
        ),
      ],
      const SizedBox(height: 12),
      AppTextarea(controller: _notes, hintText: 'Notes (optional)', rows: 2, onChanged: (v) => setState(() => _draft.notes = v)),
      const SizedBox(height: 16),
      _sectionLabel('What will happen'),
      Row(children: [
        Expanded(child: _figure('Sold', _n(totals.sold), TColors.emerald700)),
        const SizedBox(width: 8),
        Expanded(child: _figure('Culled', _n(totals.culled), TColors.slate700)),
        const SizedBox(width: 8),
        Expanded(child: _figure('Transferred', _n(totals.transferred), _violet700)),
      ]),
      if (_draft.sales.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          '${_draft.sales.length == 1 ? 'This sale' : 'These ${_draft.sales.length} sales'} will be created on the Sales page when you close the flock:',
          style: const TextStyle(fontSize: 13, color: TColors.slate600),
        ),
        for (final s in _draft.sales) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
            child: Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, runSpacing: 2, children: [
              Text(
                '${_n(s.quantity)} birds${s.customerName.trim().isNotEmpty ? ' to ${s.customerName.trim()}' : ''}'
                ' · ${paymentTermsLabel(s.paymentTerms)}'
                '${s.paymentTerms == 'PartPaid' && (s.amountPaid ?? 0) != 0 ? ' (${_money(s.amountPaid)} now)' : ''}',
                style: const TextStyle(fontSize: 13),
              ),
              Text(_money(saleTotal(s)), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      ],
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.home_outlined, size: 16, color: TColors.slate400),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            house.isNotEmpty
                ? '$house will be released for a new flock. The flock keeps its house in its history.'
                : 'This flock has no house assigned.',
            style: const TextStyle(fontSize: 13, color: TColors.slate600),
          ),
        ),
      ]),
    ]);
  }
}

/// One sale in step 2, with its own text controllers.
class _SaleCard extends StatefulWidget {
  const _SaleCard({
    super.key,
    required this.index,
    required this.sale,
    required this.customers,
    required this.cash,
    required this.onChanged,
    required this.onRemove,
  });
  final int index;
  final CloseoutSale sale;
  final List<String> customers;
  final List<Map> cash;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_SaleCard> createState() => _SaleCardState();
}

String _shown(num v) => v == 0 ? '' : jsNum(v);

class _SaleCardState extends State<_SaleCard> {
  CloseoutSale get s => widget.sale;
  late final _qty = TextEditingController(text: _shown(s.quantity));
  late final _price = TextEditingController(text: _shown(s.unitPrice));
  late final _total = TextEditingController(text: _shown(saleTotal(s)));
  late final _paid = TextEditingController(text: s.amountPaid == null ? '' : jsNum(s.amountPaid!));

  @override
  void dispose() {
    for (final c in [_qty, _price, _total, _paid]) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncTotal() => _total.text = _shown(saleTotal(s));

  void _set(VoidCallback f) {
    f();
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cashItems = [
      for (final a in widget.cash)
        if (tIntOrNull(a['poultryCashAccountId']) != null)
          AppSelectItem<int?>(value: tIntOrNull(a['poultryCashAccountId']), label: tStr(a['accountName'])),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Sale ${widget.index + 1}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
          IconButton(
            tooltip: 'Remove sale',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600),
            onPressed: widget.onRemove,
          ),
        ]),
        const SizedBox(height: 4),
        _pair(
          _label(
            'Birds',
            AppNumberInput(
              controller: _qty,
              hintText: '',
              onChanged: (v) => _set(() {
                s.quantity = _parse(v) ?? 0;
                if (s.totalAmount == null) _syncTotal();
              }),
            ),
          ),
          _label(
            'Price per bird',
            AppNumberInput(
              controller: _price,
              hintText: '',
              allowDecimal: true,
              onChanged: (v) => _set(() {
                s.unitPrice = _parse(v) ?? 0;
                s.totalAmount = null;
                _syncTotal();
              }),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _label(
          'Total price',
          AppNumberInput(
            controller: _total,
            hintText: '',
            allowDecimal: true,
            onChanged: (v) => _set(() => s.totalAmount = _parse(v)),
          ),
        ),
        const SizedBox(height: 12),
        _label(
          'Customer${s.paymentTerms == 'Paid' ? ' (optional)' : ''}',
          Autocomplete<String>(
            initialValue: TextEditingValue(text: s.customerName),
            optionsBuilder: (v) => widget.customers.where((c) => c.toLowerCase().contains(v.text.toLowerCase())),
            onSelected: (v) => _set(() => s.customerName = v),
            fieldViewBuilder: (context, controller, focus, onSubmit) => TextFormField(
              controller: controller,
              focusNode: focus,
              decoration: const InputDecoration(hintText: 'Customer name'),
              onChanged: (v) => _set(() => s.customerName = v),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _label(
          'Payment terms',
          AppSelect<String>(
            value: s.paymentTerms,
            items: [for (final (v, l) in closeoutPaymentTerms) AppSelectItem(value: v, label: l)],
            onChanged: (v) => _set(() => s.paymentTerms = v ?? s.paymentTerms),
          ),
        ),
        if (s.paymentTerms == 'PartPaid') ...[
          const SizedBox(height: 12),
          _label(
            'Amount received now',
            AppNumberInput(
              controller: _paid,
              hintText: '',
              allowDecimal: true,
              onChanged: (v) => _set(() => s.amountPaid = _parse(v)),
            ),
          ),
        ],
        if (s.paymentTerms != 'Credit') ...[
          const SizedBox(height: 12),
          _label(
            'Payment method',
            AppSelect<String>(
              value: closeoutPaymentMethods.contains(s.paymentMethod) ? s.paymentMethod : null,
              hintText: 'How was it paid?',
              items: [for (final m in closeoutPaymentMethods) AppSelectItem(value: m, label: m)],
              onChanged: (v) => _set(() => s.paymentMethod = v),
            ),
          ),
          const SizedBox(height: 12),
          _label(
            'Received into',
            AppSelect<int?>(
              value: cashItems.any((i) => i.value == s.cashAccountId) ? s.cashAccountId : null,
              hintText: 'Cash account',
              items: cashItems,
              onChanged: (v) => _set(() => s.cashAccountId = v),
            ),
          ),
        ],
      ]),
    );
  }
}

/// A cull or transfer row: Birds, a text field, and remove.
class _LineRow extends StatefulWidget {
  const _LineRow({
    super.key,
    required this.quantity,
    required this.textLabel,
    required this.textHint,
    required this.text,
    required this.onQuantity,
    required this.onText,
    required this.onRemove,
  });
  final num quantity;
  final String textLabel, textHint, text;
  final ValueChanged<num> onQuantity;
  final ValueChanged<String> onText;
  final VoidCallback onRemove;

  @override
  State<_LineRow> createState() => _LineRowState();
}

class _LineRowState extends State<_LineRow> {
  late final _qty = TextEditingController(text: _shown(widget.quantity));
  late final _text = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _qty.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          SizedBox(
            width: 84,
            child: _label('Birds', AppNumberInput(controller: _qty, hintText: '', onChanged: (v) => widget.onQuantity(_parse(v) ?? 0))),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _label(widget.textLabel, AppInput(controller: _text, hintText: widget.textHint, onChanged: widget.onText)),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600),
            onPressed: widget.onRemove,
          ),
        ]),
      );
}

// ===========================================================================
// Lifetime view
// ===========================================================================

/// Flock lifetime performance + closeout history + Reopen. [page] is the full
/// page's layout, otherwise the quick-look dialog's.
class FlockLifetimeView extends StatefulWidget {
  const FlockLifetimeView({
    super.key,
    required this.session,
    required this.company,
    required this.flockId,
    this.page = false,
    this.canReopen = false,
    this.onReopened,
    this.onLoaded,
  });
  final Session session;
  final Company company;
  final int flockId;
  final bool page;
  final bool canReopen;
  final VoidCallback? onReopened;
  final ValueChanged<Map?>? onLoaded;

  @override
  State<FlockLifetimeView> createState() => _FlockLifetimeViewState();
}

class _FlockLifetimeViewState extends State<FlockLifetimeView> {
  late final _api = FlockCloseoutApi(widget.session, widget.company);
  bool _loading = true;
  String _error = '';
  Map? _summary;
  List<Map> _history = [];
  bool _reopening = false;
  bool _reopenOpen = false;
  final _reopenReason = TextEditingController();

  // 339: reversing the closeout's sales is the default.
  bool _reverseSales = true;
  ({bool ok, String text, List<String> warnings})? _reopenMessage;
  FarmMoney _money = const FarmMoney();

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    _load();
  }

  @override
  void dispose() {
    _reopenReason.dispose();
    super.dispose();
  }

  String _m(Object? v) => v == null ? '—' : _money(tNum(v));

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    Object? s;
    String? sErr;
    Object? h;
    await Future.wait([
      _api.lifetime(flockId: widget.flockId).then((v) => s = v, onError: (Object e) {
        sErr = e is ApiException ? e.message : '$e';
        return null;
      }),
      _api.history(widget.flockId).then((v) => h = v, onError: (Object _) => null),
    ]);
    if (!mounted) return;
    final rows = rowsOf(s);
    final row = rows.isNotEmpty ? rows.first : null;
    setState(() {
      if (sErr != null) {
        _error = sErr!.isNotEmpty ? sErr! : "Could not load this flock's performance.";
      } else if (rows.isEmpty) {
        _error = 'This flock was not found on the current company.';
      }
      _summary = row;
      _history = rowsOf(h);
      _loading = false;
    });
    widget.onLoaded?.call(row);
  }

  Future<void> _doReopen() async {
    setState(() => _reopening = true);
    Map? res;
    String message = '';
    try {
      final r = await _api.reopen(widget.flockId, _reopenReason.text.trim(), _reverseSales);
      res = r is Map ? r : null;
    } on ApiException catch (e) {
      res = e.body is Map ? e.body as Map : null;
      message = e.message;
    }
    if (!mounted) return;
    setState(() => _reopening = false);
    if (res != null && res['success'] == true) {
      setState(() {
        _reopenMessage = (
          ok: true,
          text: tStr(res!['message']),
          warnings: res['warnings'] is List ? [for (final w in res['warnings'] as List) tStr(w)] : <String>[],
        );
        _reopenOpen = false;
        _reopenReason.clear();
      });
      await _load();
      widget.onReopened?.call();
    } else {
      final msg = tStr(res?['message']);
      setState(() => _reopenMessage = (
            ok: false,
            text: msg.isNotEmpty ? msg : (message.isNotEmpty ? message : 'The flock could not be reopened.'),
            warnings: const <String>[],
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    if (_loading && s == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Loading…', style: TextStyle(color: TColors.slate500)),
        ]),
      );
    }

    final messages = <Widget>[
      if (_error.isNotEmpty) closeoutAlert(_error, tone: 'error'),
      if (_reopenMessage != null)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _reopenMessage!.ok ? TColors.emerald50 : TColors.rose50,
            border: Border.all(color: _reopenMessage!.ok ? TColors.emerald200 : TColors.rose200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_reopenMessage!.text,
                style: TextStyle(fontSize: 13, color: _reopenMessage!.ok ? TColors.emerald900 : const Color(0xFF881337))),
            for (final w in _reopenMessage!.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(w, style: const TextStyle(fontSize: 13, color: TColors.amber800)),
              ),
          ]),
        ),
    ];

    if (s == null) return _stack(messages, 12);

    final isClosed = tStr(s['status']) == 'Closed';
    final page = widget.page;
    final children = <Widget>[
      ...messages,
      _summaryCard(s, isClosed),
      ..._sections(s, isClosed),
      ?_reopenBlock(isClosed),
      if (_history.isNotEmpty)
        _historyBlock()
      else if (page)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .6),
            border: Border.all(color: TColors.slate300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.history, size: 20, color: TColors.slate400),
            const SizedBox(height: 8),
            Text(
              isClosed
                  ? 'No closeout history.'
                  : 'This flock has not been closed yet. Use Close flock at the top of the page when its life is over.',
              style: const TextStyle(fontSize: 13, color: TColors.slate500),
            ),
          ]),
        ),
    ];
    return _stack(children, page ? 16 : 16);
  }

  Widget _stack(List<Widget> c, double gap) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < c.length; i++) ...[if (i > 0) SizedBox(height: gap), c[i]],
      ]);

  Widget _summaryCard(Map s, bool isClosed) {
    final mortality = s['lifetimeMortalityRate'] ?? s['trackedMortalityRate'];
    final profit = tNum(s['profit']);
    final meta = <Widget>[
      TBadge(tStr(s['status']),
          bg: isClosed ? TColors.slate100 : TColors.emerald50,
          fg: isClosed ? TColors.slate800 : TColors.emerald800,
          border: isClosed ? TColors.slate400 : TColors.emerald300),
      _meta(Icons.calendar_today_outlined,
          '${_day(s['startDate'])} → ${tStr(s['closedDate']).isNotEmpty ? _day(s['closedDate']) : 'today'}',
          extra: ' (${_n(tNum(s['daysInProduction']))} days)'),
      if (tStr(s['breed']).isNotEmpty) _meta(Icons.flutter_dash, tStr(s['breed'])),
      if (tStr(s['batchCode']).isNotEmpty) _meta(Icons.sell_outlined, 'Batch ${tStr(s['batchCode'])}'),
      if (tStr(s['houseName']).isNotEmpty) Text('House: ${tStr(s['houseName'])}', style: const TextStyle(fontSize: 13, color: TColors.slate600)),
    ];
    final heads = <Widget>[
      _headline('Profit', _m(s['profit']), tone: profit >= 0 ? TColors.emerald700 : TColors.rose700, sub: '${_m(s['profitPerOriginalBird'])} per bird placed'),
      _headline('Total revenue', _m(s['totalRevenue']), tone: TColors.emerald700),
      _headline('Total cost', _m(s['totalCost']), tone: TColors.rose700),
      _headline(isClosed ? 'Final birds' : 'Current birds', _n(tNum(s['finalBirds'])), sub: 'of ${_n(tNum(s['originallyPlaced']))} placed'),
      _headline('Mortality', _pct(mortality), sub: s['lifetimeMortalityRate'] != null ? 'Lifetime rate' : 'Tracked rate'),
      _headline('Total eggs', _n(tNum(s['totalEggs'])), sub: '${_n(tNum(s['productionDays']))} production days'),
    ];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xB3F8FAFC),
            border: Border(bottom: BorderSide(color: TColors.slate100)),
          ),
          child: Wrap(spacing: 20, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: meta),
        ),
        Container(
          color: TColors.slate100,
          child: LayoutBuilder(builder: (context, c) {
            final w = (c.maxWidth - 1) / 2;
            return Wrap(spacing: 1, runSpacing: 1, children: [for (final h in heads) SizedBox(width: w, child: h)]);
          }),
        ),
      ]),
    );
  }

  Widget _meta(IconData icon, String text, {String? extra}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: TColors.slate400),
        const SizedBox(width: 6),
        Flexible(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: text),
              if (extra != null) TextSpan(text: extra, style: const TextStyle(color: TColors.slate400)),
            ]),
            style: const TextStyle(fontSize: 13, color: TColors.slate600),
          ),
        ),
      ]);

  Widget _headline(String label, String value, {Color? tone, String? sub}) => Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.slate500)),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: widget.page ? 22 : 19, fontWeight: FontWeight.w600, color: tone ?? TColors.slate900)),
          if (sub != null)
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: TColors.slate400)),
        ]),
      );

  Widget _figure(String label, String value, {Color? tone, String? hint}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate100), borderRadius: BorderRadius.circular(6)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: tone ?? TColors.slate900)),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint, style: const TextStyle(fontSize: 11, color: TColors.slate400)),
          ],
        ]),
      );

  /// A grid of [cols] equal columns.
  Widget _grid(List<Widget> tiles, {int cols = 2}) => LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - 10 * (cols - 1)) / cols;
        return Wrap(spacing: 10, runSpacing: 10, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
      });

  Widget _panel(String title, IconData icon, Color tileBg, Color tileFg, Widget child, {String? note}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: TColors.slate200),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: tileBg, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 16, color: tileFg),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TColors.slate800))),
          ]),
          const SizedBox(height: 12),
          child,
          if (note != null) ...[
            const SizedBox(height: 12),
            Text(note, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          ],
        ]),
      );

  List<Widget> _sections(Map s, bool isClosed) {
    final hasOpening = s['hasOpeningPosition'] == true;
    final historyKnown = s['historyKnown'] == true;
    final feedPerDozen = s['feedKgPerDozenEggs'];
    final profit = tNum(s['profit']);
    return [
      _panel(
          'Birds',
          Icons.flutter_dash,
          _sky50,
          _sky600,
          _grid([
            _figure('Originally placed', _n(tNum(s['originallyPlaced']))),
            _figure(isClosed ? 'Final birds' : 'Current birds', _n(tNum(s['finalBirds']))),
            _figure('Sold', _n(tNum(s['birdsSold'])), tone: TColors.emerald700),
            _figure('Culled / transferred', '${_n(tNum(s['birdsCulled']))} / ${_n(tNum(s['birdsTransferred']))}'),
          ])),
      _panel(
          'Mortality',
          Icons.monitor_heart_outlined,
          TColors.rose50,
          TColors.rose600,
          _grid([
            _figure('Recorded here', _n(tNum(s['recordedMortality'])), tone: TColors.rose700),
            _figure('Tracked rate', _pct(s['trackedMortalityRate']), hint: hasOpening ? 'Of the opening position' : 'Of birds placed'),
            _figure('Before tracking', !hasOpening ? '—' : (historyKnown ? _n(tNum(s['openingMortality'])) : '—'),
                hint: !hasOpening ? 'Tracked from placement' : (historyKnown ? 'Opening historical mortality' : 'History not recorded')),
            _figure('Lifetime rate', _pct(s['lifetimeMortalityRate']), hint: s['lifetimeMortalityRate'] == null ? 'Opening losses unknown' : null),
          ])),
      _panel(
          'Production',
          Icons.egg_outlined,
          TColors.amber50,
          TColors.amber600,
          _grid([
            _figure('Total eggs', _n(tNum(s['totalEggs']))),
            _figure('Production days', _n(tNum(s['productionDays']))),
            _figure('Feed consumed', '${_n(tNum(s['feedConsumedKg']).round())} kg'),
            _figure('Feed per dozen', feedPerDozen == null ? '—' : '${tNum(feedPerDozen).toStringAsFixed(3)} kg',
                hint: feedPerDozen == null ? 'No eggs recorded' : null),
          ])),
      _panel(
          'Revenue',
          Icons.trending_up,
          TColors.emerald50,
          TColors.emerald600,
          _grid([
            _figure('Eggs', _m(s['eggRevenue'])),
            _figure('Bird sales', _m(s['birdSaleRevenue'])),
            _figure('Other', _m(s['otherRevenue'])),
            _figure('Total revenue', _m(s['totalRevenue']), tone: TColors.emerald700),
          ]),
          note: 'Sales recorded against this flock. Sales entered without a flock are not attributed to it.'),
      _panel(
          'Attributable cost',
          Icons.receipt_long_outlined,
          _orange50,
          _orange600,
          _grid([
            _figure('Feed issued', _m(s['feedCost'])),
            _figure('Medication', _m(s['medicationCost'])),
            _figure('Bird cost', _m(s['birdCost']), hint: s['birdCostRecorded'] == true ? 'Share of batch cost' : 'Batch has no cost'),
            _figure('Labour (tagged)', _m(s['laborCost'])),
            _figure('Other (tagged)', _m(s['otherDirectCost'])),
            _figure('Total cost', _m(s['totalCost']), tone: TColors.rose700),
          ]),
          note: 'Untagged payroll and overheads are not spread across flocks — there is no rule to split them by.'),
      _panel(
          'Result',
          Icons.account_balance_wallet_outlined,
          TColors.violet50,
          TColors.violet600,
          widget.page
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _figure('Profit', _m(s['profit']), tone: profit >= 0 ? TColors.emerald700 : TColors.rose700),
                  const SizedBox(height: 10),
                  _grid([
                    _figure('Per original bird', _m(s['profitPerOriginalBird'])),
                    _figure('Revenue per bird', _m(s['revenuePerOriginalBird'])),
                  ]),
                ])
              : _grid([
                  _figure('Profit', _m(s['profit']), tone: profit >= 0 ? TColors.emerald700 : TColors.rose700),
                  _figure('Per original bird', _m(s['profitPerOriginalBird'])),
                  _figure('Revenue per bird', _m(s['revenuePerOriginalBird'])),
                ], cols: 1)),
    ];
  }

  Widget _historyBlock() => _panel(
        'Closeout history',
        Icons.history,
        TColors.slate100,
        TColors.slate600,
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < _history.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _historyCard(_history[i]),
          ],
        ]),
      );

  Widget _historyCard(Map h) {
    final reopened = tStr(h['reopenedAt']).isNotEmpty;
    final dispositions = h['dispositions'] is List ? [for (final d in h['dispositions'] as List) if (d is Map) d] : <Map>[];
    final correction = tNum(h['correction']);
    const small = TextStyle(fontSize: 12, color: TColors.slate600);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: reopened ? Colors.white : const Color(0x99EFF6FF),
        border: Border.all(color: reopened ? TColors.slate200 : TColors.blue200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
          Text('Closed ${_day(h['closedDate'])} — ${tStr(h['reason'])}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          TBadge(reopened ? 'Reopened' : 'Current', bg: Colors.white, fg: TColors.slate900, border: TColors.slate300),
        ]),
        const SizedBox(height: 4),
        Text(
          '${_n(tNum(h['liveBirdsAtCloseout']))} standing at close: ${_n(tNum(h['disposedSold']))} sold, ${_n(tNum(h['disposedCulled']))} culled, '
          '${_n(tNum(h['disposedTransferred']))} transferred. Closed by ${tStr(h['closedBy'])}.'
          '${correction != 0 ? ' Count corrections of ${correction > 0 ? '+' : ''}${_n(correction)} were on record.' : ''}',
          style: small,
        ),
        for (final d in dispositions.where((d) => d['disposition'] == 'Sale'))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Sale #${tStr(d['saleId'])}: ${_n(tNum(d['quantity']))} birds'
              '${d['totalAmount'] != null ? ' for ${_m(d['totalAmount'])}' : ''}'
              '${tStr(d['customerName']).isNotEmpty ? ' to ${tStr(d['customerName'])}' : ''}'
              '${tStr(d['saleReversedAt']).isNotEmpty ? ' — reversed on reopen ${_day(d['saleReversedAt'])} (payments reversed, sale removed)' : (d['paid'] == false ? ' (balance outstanding)' : '')}',
              style: small,
            ),
          ),
        for (final d in dispositions.where((d) => d['disposition'] == 'Transfer'))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Transferred ${_n(tNum(d['quantity']))} to ${tStr(d['destination'])}', style: small),
          ),
        if (reopened)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Reopened ${_day(h['reopenedAt'])} by ${tStr(h['reopenedBy'])}: ${tStr(h['reopenReason'])}', style: small),
          ),
      ]),
    );
  }

  Widget? _reopenBlock(bool isClosed) {
    if (!isClosed || !widget.canReopen) return null;
    final current = _history.where((h) => tStr(h['reopenedAt']).isEmpty);
    final currentDispositions = current.isNotEmpty && current.first['dispositions'] is List ? current.first['dispositions'] as List : const [];
    final hasSales = currentDispositions.any((d) => d is Map && d['disposition'] == 'Sale');
    return _panel(
      'Reopen this flock',
      Icons.restart_alt,
      TColors.amber50,
      TColors.amber600,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Closed in error? Reopening makes the flock active again.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
        const SizedBox(height: 12),
        if (!_reopenOpen)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _reopenOpen = true),
              icon: const Icon(Icons.restart_alt, size: 16),
              label: const Text('Reopen flock'),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: TColors.amber200), borderRadius: BorderRadius.circular(6)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Reopening makes the flock active again and undoes its culls and transfers. This is recorded.',
                  style: TextStyle(fontSize: 13, color: TColors.amber900)),
              if (hasSales) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => setState(() => _reverseSales = !_reverseSales),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Checkbox(
                      value: _reverseSales,
                      visualDensity: VisualDensity.compact,
                      onChanged: (v) => setState(() => _reverseSales = v == true),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text.rich(
                          TextSpan(children: [
                            const TextSpan(text: 'Also reverse the closeout sales. ', style: TextStyle(fontWeight: FontWeight.w500)),
                            TextSpan(
                                text: _reverseSales
                                    ? 'Their payments are reversed (kept on record as Reversed), the money is taken back out of the cash account, the sales are removed and the birds return to the flock.'
                                    : 'The sales stay — use this only if the birds really were sold. They can then be edited on the Sales page.'),
                          ]),
                          style: const TextStyle(fontSize: 13, color: TColors.amber900),
                        ),
                      ),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 8),
              const Text('Reason for reopening', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.slate700)),
              const SizedBox(height: 4),
              AppTextarea(controller: _reopenReason, rows: 2, onChanged: (_) => setState(() {})),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                OutlinedButton(
                  onPressed: _reopening ? null : () => setState(() => _reopenOpen = false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: _reopening || _reopenReason.text.trim().isEmpty ? null : _doReopen,
                  icon: _reopening
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const SizedBox.shrink(),
                  label: const Text('Reopen'),
                ),
              ]),
            ]),
          ),
      ]),
    );
  }
}

/// The quick look: FlockLifetimeView in a dialog, with "Open full page".
Future<void> showFlockLifetimeDialog(BuildContext context,
    {required Session session,
    required Company company,
    required int flockId,
    required bool canReopen,
    VoidCallback? onReopened,
    required VoidCallback onOpenPage}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _LifetimeDialog(
      session: session,
      company: company,
      flockId: flockId,
      canReopen: canReopen,
      onReopened: onReopened,
      onOpenPage: () {
        Navigator.of(ctx).pop();
        onOpenPage();
      },
    ),
  );
}

class _LifetimeDialog extends StatefulWidget {
  const _LifetimeDialog({
    required this.session,
    required this.company,
    required this.flockId,
    required this.canReopen,
    this.onReopened,
    required this.onOpenPage,
  });
  final Session session;
  final Company company;
  final int flockId;
  final bool canReopen;
  final VoidCallback? onReopened;
  final VoidCallback onOpenPage;

  @override
  State<_LifetimeDialog> createState() => _LifetimeDialogState();
}

class _LifetimeDialogState extends State<_LifetimeDialog> {
  String? _name;

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        backgroundColor: TColors.slate50,
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        title: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.bar_chart, size: 20, color: TColors.slate600),
            const SizedBox(width: 8),
            Flexible(
              child: Text('${_name ?? 'Flock'} — lifetime performance', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
          ]),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: widget.onOpenPage,
            icon: const Icon(Icons.open_in_new, size: 14),
            label: const Text('Open full page'),
          ),
        ]),
        content: SizedBox(
          width: 640,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              'Everything this flock produced, earned and cost. Only costs that belong to the flock are counted: feed and medication issued to it, its share of the batch\'s bird cost, and expenses tagged to it.',
              style: TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 16),
            FlockLifetimeView(
              session: widget.session,
              company: widget.company,
              flockId: widget.flockId,
              canReopen: widget.canReopen,
              onReopened: widget.onReopened,
              onLoaded: (s) => setState(() => _name = s == null ? null : tStr(s['flockName'])),
            ),
          ]),
        ),
        actions: [OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      );
}
