// One delivery run (app/poultry-driver-returns/[id]/page.tsx): the header,
// four figures, products loaded, the reversal history, the return's
// reconciliation, money collected, the customer breakdown, delivery expenses
// and the audit trail.

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../money/money_widgets.dart';
import '../reports/report_format.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, jsNum, loc;
import '../trackers/tracker_widgets.dart';
import 'delivery_logic.dart';

class DeliveryDetailScreen extends StatefulWidget {
  const DeliveryDetailScreen({super.key, required this.session, required this.company, required this.loadingId});
  final Session session;
  final Company company;
  final int loadingId;

  @override
  State<DeliveryDetailScreen> createState() => _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends State<DeliveryDetailScreen> {
  Map? _loading, _ret;
  List<Map> _items = [], _retItems = [], _sales = [], _expenses = [];
  bool _busy = true;
  FarmMoney _fmt = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  Map<String, String> get _q => {'farmId': widget.company.farmId};

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

  Future<List<Map>> _list(String path) async {
    try {
      return rowsOf(await _api.get(path, query: _q));
    } on ApiException {
      return [];
    }
  }

  Future<void> _load() async {
    final id = widget.loadingId;
    try {
      final r = await Future.wait<Object?>([
        _api.get('/api/Poultry/vehicle-loadings/$id', query: _q).then<Object?>((v) => v).catchError((_) => null),
        _api.get('/api/Poultry/driver-returns', query: _q),
        _list('/api/Poultry/vehicle-loadings/$id/items'),
      ]);
      if (!mounted) return;
      final l = r[0] is Map ? r[0] as Map : null;
      if (l == null) {
        trackerToast(context, 'Delivery run not found', description: 'Delivery run #$id not found. It may have been deleted.', error: true);
        setState(() {
          _loading = null;
          _busy = false;
        });
        return;
      }
      final ret = pickRunReturn(rowsOf(r[1]), id);
      var ri = <Map>[], cs = <Map>[], ex = <Map>[];
      if (ret != null) {
        final rid = tStr(ret['poultryDriverReturnId']);
        final x = await Future.wait([
          _list('/api/Poultry/driver-returns/$rid/items'),
          _list('/api/Poultry/driver-returns/$rid/customer-sales'),
          _list('/api/Poultry/driver-returns/$rid/expenses'),
        ]);
        ri = x[0];
        cs = x[1];
        ex = x[2];
      }
      if (!mounted) return;
      setState(() {
        _loading = l;
        _items = r[2] as List<Map>;
        _ret = ret;
        _retItems = ri;
        _sales = cs;
        _expenses = ex;
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load delivery run', description: e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _badge(Object? status) {
    final (bg, fg) = loadStatusTone(status);
    return TBadge(tStr(status), bg: bg, fg: fg);
  }

  Widget _section(String title, IconData? icon, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              if (icon != null) ...[Icon(icon, size: 16, color: TColors.slate500), const SizedBox(width: 6)],
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate800))),
            ]),
            const SizedBox(height: 10),
            child,
          ]),
        ),
      );

  Widget _empty(String t) => Text(t, style: const TextStyle(fontSize: 12, color: TColors.slate500));

  num _itemExpected(Map it) => it['expectedAmount'] != null ? tNum(it['expectedAmount']) : tNum(it['cratesLoaded']) * tNum(it['unitPrice']);
  num _retSales(Map ri) => ri['expectedSales'] != null ? tNum(ri['expectedSales']) : tNum(ri['cratesSold']) * tNum(ri['unitPrice']);
  String _pname(Map it) => tStr(it['productName']).isNotEmpty ? tStr(it['productName']) : 'Product #${tStr(it['poultryProductId'])}';

  @override
  Widget build(BuildContext context) {
    final l = _loading;
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery run')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back to Deliveries'),
            ),
          ),
          const SizedBox(height: 8),
          if (_busy)
            const TCard(child: Text('Loading delivery run…', style: TextStyle(color: TColors.slate500)))
          else if (l == null)
            const TCard(child: Text('Delivery run not found.', style: TextStyle(color: TColors.slate500)))
          else
            ..._body(l),
        ],
      ),
    );
  }

  List<Widget> _body(Map l) {
    final fmt = _fmt;
    final ret = _ret;
    final totalExpected = _items.fold<num>(0, (s, it) => s + _itemExpected(it));
    final expectedCash = totalExpected != 0 ? totalExpected : tNum(l['expectedCash']);
    final collected = ret == null
        ? 0
        : tNum(ret['cashCollected']) + tNum(ret['moMoCollected']) + tNum(ret['bankCollected']) + tNum(ret['creditSalesAmount']);
    final expTotal = _expenses.where((e) => e['isApproved'] == true).fold<num>(0, (s, e) => s + tNum(e['amount']));
    final short = tNum(ret?['shortageAmount']);
    final loadedSum = _items.fold<num>(0, (s, it) => s + tNum(it['cratesLoaded']));
    final loadedText = loc(loadedSum);

    Widget summary(String label, String value, {Color? color}) => TCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: color)),
          ]),
        );

    return [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: TColors.sky100, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.local_shipping_outlined, size: 20, color: TColors.sky700),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Delivery run #${tStr(l['poultryVehicleLoadingId'])}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900)),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _badge(l['status']),
              Text(fmtDateTime(l['loadDate'], l, _offset), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              if (tStr(l['driverName']).isNotEmpty)
                Text.rich(TextSpan(children: [
                  const TextSpan(text: '· Driver: '),
                  TextSpan(text: tStr(l['driverName']), style: const TextStyle(fontWeight: FontWeight.w700)),
                ]), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              if (tStr(l['vehicleName']).isNotEmpty) Text('· ${tStr(l['vehicleName'])}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              if (tStr(l['routeName']).isNotEmpty) Text('· ${tStr(l['routeName'])}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
          ]),
        ),
      ]),
      const SizedBox(height: 14),
      twoUp([
        summary('Total loaded (crates)', loadedText.isNotEmpty ? loadedText : jsNum(tNum(l['cratesLoaded']))),
        summary('Expected', fmt(expectedCash)),
        summary('Collected', ret != null ? fmt(collected) : '—'),
        summary(
          short > 0 ? 'Shortage' : 'Overage',
          ret != null ? fmt(short > 0 ? short : tNum(ret['overageAmount'])) : '—',
          color: short > 0 ? TColors.rose600 : TColors.emerald600,
        ),
      ]),
      const SizedBox(height: 14),
      _section(
        'Products loaded',
        Icons.inventory_2_outlined,
        _items.isEmpty
            ? _empty('No item rows. Legacy single-product loading.')
            : MobileCardList<Map>(
                items: _items,
                keyOf: (it) => tStr(it['poultryVehicleLoadingItemId']),
                primary: _pname,
                secondary: (it) => '${jsNum(tNum(it['cratesLoaded']))} crates · ${fmt(_itemExpected(it))}',
                details: (it) => [
                  ('Loaded (crates)', jsNum(tNum(it['cratesLoaded']))),
                  ('Eggs / crate', jsNum(tNum(it['eggsPerCrate']))),
                  ('Unit price', fmt(tNum(it['unitPrice']))),
                  ('Expected', fmt(_itemExpected(it))),
                ],
                alwaysExpanded: true,
                table: (_) => const SizedBox.shrink(),
              ),
      ),
      if (RegExp('reversed by', caseSensitive: false).hasMatch(tStr(ret?['notes'])))
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: TColors.amber200), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Reversal history', style: TextStyle(fontWeight: FontWeight.w600, color: TColors.amber900)),
              const SizedBox(height: 4),
              Text(tStr(ret?['notes']), style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: TColors.amber900)),
            ]),
          ),
        ),
      if (ret != null) ...[
        _section(
          'Return reconciliation',
          Icons.receipt_long_outlined,
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _badge(ret['status']),
              Text('Return date: ${fmtDateTime(ret['returnDate'], ret, _offset)}', style: const TextStyle(fontSize: 12, color: TColors.slate600)),
            ]),
            const SizedBox(height: 10),
            if (_retItems.isNotEmpty)
              MobileCardList<Map>(
                items: _retItems,
                keyOf: (ri) => tStr(ri['poultryDriverReturnItemId']),
                primary: _pname,
                secondary: (ri) => 'Sold ${jsNum(tNum(ri['cratesSold']))} · ${fmt(_retSales(ri))}',
                details: (ri) => [
                  ('Loaded', jsNum(tNum(ri['cratesLoaded']))),
                  ('Sold', jsNum(tNum(ri['cratesSold']))),
                  ('Returned', jsNum(tNum(ri['cratesReturned']))),
                  ('Damaged', jsNum(tNum(ri['cratesDamaged']))),
                  ('Unit price', fmt(tNum(ri['unitPrice']))),
                  ('Sales', fmt(_retSales(ri))),
                ],
                alwaysExpanded: true,
                table: (_) => const SizedBox.shrink(),
              )
            else
              _empty('Legacy single-product return — totals: sold ${jsNum(tNum(ret['cratesSold']))}, returned ${jsNum(tNum(ret['cratesReturned']))}, '
                  'damaged ${jsNum(tNum(ret['cratesDamaged']))}.'),
          ]),
        ),
        _section(
          'Money collected',
          Icons.payments_outlined,
          LayoutBuilder(builder: (context, c) {
            final w = (c.maxWidth - 8) / 2;
            Widget tile(String label, num v, {bool rose = false}) => SizedBox(
                  width: w,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                      Text(fmt(v), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: rose ? TColors.rose600 : null)),
                    ]),
                  ),
                );
            return Wrap(spacing: 8, runSpacing: 8, children: [
              tile('Cash', tNum(ret['cashCollected'])),
              tile('MoMo', tNum(ret['moMoCollected'])),
              tile('Bank', tNum(ret['bankCollected'])),
              tile('Credit sales', tNum(ret['creditSalesAmount']), rose: tNum(ret['creditSalesAmount']) > 0),
              tile('Driver float returned', tNum(ret['cashReturnedByDriver'])),
              tile('Unaccounted cash', short, rose: short > 0),
            ]);
          }),
        ),
        _section(
          'Customer sales breakdown (${_sales.length})',
          Icons.people_outline,
          _sales.isEmpty
              ? _empty('Summary-only return — no per-customer breakdown was recorded.')
              : Column(children: [for (final cs in _sales) _customerSale(cs, fmt)]),
        ),
        _section(
          'Delivery expenses (${fmt(expTotal)})',
          Icons.payments_outlined,
          _expenses.isEmpty
              ? _empty('No delivery expenses logged.')
              : MobileCardList<Map>(
                  items: _expenses,
                  keyOf: (e) => tStr(e['poultryDriverDeliveryExpenseId']),
                  primary: (e) => tStr(e['expenseCategory']),
                  secondaryBuilder: (e) => Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(fmt(tNum(e['amount']))),
                    e['isApproved'] == true
                        ? const TBadge('Approved', bg: TColors.green100, fg: TColors.green700)
                        : const TBadge('Pending', bg: TColors.amber100, fg: TColors.amber700),
                  ]),
                  details: (e) => [
                    ('Amount', fmt(tNum(e['amount']))),
                    ('Description', tStr(e['description']).isEmpty ? '—' : tStr(e['description'])),
                    ('Status', e['isApproved'] == true ? 'Approved' : 'Pending'),
                  ],
                  alwaysExpanded: true,
                  table: (_) => const SizedBox.shrink(),
                ),
        ),
      ] else
        _section(
          'Return reconciliation',
          Icons.receipt_long_outlined,
          _empty('No return recorded yet. ${tStr(l['status']) == 'Loaded' ? 'Use the Record Return action on the Deliveries page.' : ''}'.trimRight()),
        ),
      _section(
        'Audit trail',
        null,
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _row('Loading created', tStr(l['loadDate']).split('T').first),
          if (tStr(l['driverName']).isNotEmpty) _row('Driver', tStr(l['driverName'])),
          if (tStr(l['vehicleName']).isNotEmpty) _row('Vehicle', tStr(l['vehicleName'])),
          if (tStr(l['routeName']).isNotEmpty) _row('Route', tStr(l['routeName'])),
          if (tNum(l['openingCashWithDriver']) != 0) _row('Opening cash float', fmt(tNum(l['openingCashWithDriver']))),
          if (tStr(l['notes']).isNotEmpty) _row('Loading notes', tStr(l['notes'])),
          if (tStr(ret?['notes']).isNotEmpty) _row('Return notes', tStr(ret?['notes'])),
        ]),
      ),
    ];
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          Text(value, style: const TextStyle(fontSize: 14, color: TColors.slate900)),
        ]),
      );

  Widget _customerSale(Map cs, FarmMoney fmt) {
    final label = tStr(cs['customerLabel']).isNotEmpty
        ? tStr(cs['customerLabel'])
        : (tIntOrNull(cs['customerId']) != null ? 'Customer #${tStr(cs['customerId'])}' : 'Walk-in');
    Widget kv(String k, String v, {TextStyle? style}) => Text.rich(TextSpan(children: [
          TextSpan(text: '$k: ', style: const TextStyle(color: TColors.slate500)),
          TextSpan(text: v, style: style),
        ]), style: const TextStyle(fontSize: 12));
    final credit = tNum(cs['creditAmount']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
          Text(
            tIntOrNull(cs['generatedSaleId']) != null && tIntOrNull(cs['generatedSaleId']) != 0
                ? 'Generated sale #${tStr(cs['generatedSaleId'])}'
                : 'No sale yet (Draft return)',
            style: const TextStyle(fontSize: 12, color: TColors.slate600),
          ),
        ]),
        const Divider(height: 16),
        Wrap(spacing: 14, runSpacing: 4, children: [
          kv('Total', fmt(tNum(cs['totalAmount'])), style: const TextStyle(fontWeight: FontWeight.w600)),
          kv('Cash', fmt(tNum(cs['cashPaid']))),
          kv('MoMo', fmt(tNum(cs['moMoPaid']))),
          kv('Bank', fmt(tNum(cs['bankPaid']))),
          kv('Credit', fmt(credit), style: credit > 0 ? const TextStyle(color: TColors.rose600, fontWeight: FontWeight.w600) : null),
        ]),
        if (tStr(cs['notes']).isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('"${tStr(cs['notes'])}"', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: TColors.slate600)),
        ],
      ]),
    );
  }
}
