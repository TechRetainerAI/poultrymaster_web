// The Deliveries page's two working dialogs, at phone width:
// "Create delivery run — load driver" and "Record driver return".

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../money/money_widgets.dart' show formSection, redCancelButton;
import '../reports/report_format.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, jsNum;
import '../trackers/tracker_widgets.dart';
import 'delivery_logic.dart';

const _indigo = Color(0xFF4F46E5), _amber = Color(0xFFD97706), _slate = Color(0xFF475569);
const _green = Color(0xFF16A34A), _purple = Color(0xFF9333EA);

/// A number box that owns its text, for rows that come and go.
class NumBox extends StatefulWidget {
  const NumBox({super.key, required this.value, required this.onChanged, this.decimal = false, this.enabled = true});
  final num value;
  final ValueChanged<num> onChanged;
  final bool decimal, enabled;
  @override
  State<NumBox> createState() => _NumBoxState();
}

class _NumBoxState extends State<NumBox> {
  late final _c = TextEditingController(text: jsNum(widget.value));

  @override
  void didUpdateWidget(NumBox old) {
    super.didUpdateWidget(old);
    if ((num.tryParse(_c.text) ?? 0) != widget.value) _c.text = jsNum(widget.value);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppInput(
        controller: _c,
        enabled: widget.enabled,
        keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(widget.decimal ? r'[0-9.]' : r'[0-9]'))],
        onChanged: (v) => widget.onChanged(num.tryParse(v) ?? 0),
      );
}

Widget _label(String text, {String? info}) => Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: Text(text, style: const TextStyle(fontSize: 12, color: TColors.slate500))),
      if (info != null) ...[
        const SizedBox(width: 4),
        Tooltip(message: info, triggerMode: TooltipTriggerMode.tap, child: const Icon(Icons.info_outline, size: 14, color: TColors.slate400)),
      ],
    ]);

Widget _field(String label, Widget child, {String? info}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700))),
          if (info != null) ...[
            const SizedBox(width: 4),
            Tooltip(message: info, triggerMode: TooltipTriggerMode.tap, child: const Icon(Icons.info_outline, size: 15, color: TColors.slate400)),
          ],
        ]),
        const SizedBox(height: 6),
        child,
      ]),
    );

/// `new Date("yyyy-mm-dd").toISOString()`.
String dayToIso(String day) => '${day}T00:00:00.000Z';

String _today() => DateTime.now().toUtc().toIso8601String().substring(0, 10);

String _productName(List<Map> products, int id) =>
    tStr(products.where((p) => tIntOrNull(p['poultryProductId']) == id).firstOrNull?['name']);

// ------------------------------------------------------------ Load vehicle

class LoadVehicleDialog extends StatefulWidget {
  const LoadVehicleDialog({
    super.key,
    required this.session,
    required this.company,
    required this.drivers,
    required this.vehicles,
    required this.routes,
    required this.products,
    required this.money,
  });
  final Session session;
  final Company company;
  final List<Map> drivers, vehicles, routes, products;
  final FarmMoney money;
  @override
  State<LoadVehicleDialog> createState() => _LoadVehicleDialogState();
}

class _LoadVehicleDialogState extends State<LoadVehicleDialog> {
  late int _vehicle = tIntOrNull(widget.vehicles.where((v) => v['status'] == 'Active').firstOrNull?['poultryVehicleId']) ?? 0;
  late int _driver = tIntOrNull(widget.drivers.where((d) => d['isActive'] == true).firstOrNull?['poultryDriverId']) ?? 0;
  late int _route = tIntOrNull(widget.routes.firstOrNull?['poultryRouteId']) ?? 0;
  num _openingCash = 0;
  String _date = _today();
  final _notes = TextEditingController();
  late final List<LoadItem> _items = widget.products.isEmpty
      ? []
      : [LoadItem(tIntOrNull(widget.products.first['poultryProductId']) ?? 0, unitPrice: tNum(widget.products.first['unitPrice']))];
  bool _saving = false;
  int _keySeed = 0;
  final List<int> _keys = [];

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _items.length; i++) {
      _keys.add(_keySeed++);
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  String get _userId => widget.session.tokens.userId ?? '';

  void _add() {
    final taken = {for (final i in _items) i.productId};
    final next = widget.products.where((p) => !taken.contains(tIntOrNull(p['poultryProductId']))).firstOrNull ?? widget.products.firstOrNull;
    if (next == null) {
      trackerToast(context, 'No more products to add', error: true);
      return;
    }
    setState(() {
      _items.add(LoadItem(tIntOrNull(next['poultryProductId']) ?? 0, unitPrice: tNum(next['unitPrice'])));
      _keys.add(_keySeed++);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final p = loadProblem(vehicleId: _vehicle, driverId: _driver, items: _items);
    if (p != null) {
      trackerToast(context, p.$1, description: p.$2, error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final created = await _api.post('/api/Poultry/vehicle-loadings', body: {
        'poultryVehicleId': _vehicle,
        'poultryDriverId': _driver == 0 ? null : _driver,
        'poultryRouteId': _route == 0 ? null : _route,
        'openingCashWithDriver': _openingCash,
        'notes': _notes.text,
        'loadDate': dayToIso(_date),
        'items': [
          for (final it in _items)
            {
              'poultryProductId': it.productId,
              'cratesLoaded': it.crates,
              'unitPrice': it.unitPrice,
              'eggsPerCrate': it.eggsPerCrate,
              'notes': it.notes.isEmpty ? null : it.notes,
            },
        ],
        'farmId': _farmId,
        'createdBy': _userId,
      });
      final id = created is Map ? tIntOrNull(created['poultryVehicleLoadingId']) : null;
      if (id == null || id == 0) throw ApiException(0, 'The load was created but the server did not return its id — please retry.');
      try {
        await _api.post('/api/Poultry/vehicle-loadings/$id/approve', query: {'farmId': _farmId, 'approvedBy': _userId});
      } on ApiException catch (e) {
        try {
          await _api.post('/api/Poultry/vehicle-loadings/$id/void', query: {'farmId': _farmId});
        } on ApiException {
          // best effort
        }
        throw ApiException(e.statusCode,
            e.message.isNotEmpty ? 'Load could not be confirmed: ${e.message}' : 'Load could not be confirmed — please retry.');
      }
      if (!mounted) return;
      trackerToast(context, 'Delivery run loaded — stock moved out');
      Navigator.pop(context, true);
      return;
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Load failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  List<AppSelectItem<int>> get _productItems =>
      [for (final p in widget.products) AppSelectItem(value: tIntOrNull(p['poultryProductId']) ?? 0, label: tStr(p['name']))];

  @override
  Widget build(BuildContext context) {
    final fmt = widget.money;
    final total = _items.fold<num>(0, (s, i) => s + i.crates * i.unitPrice);
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.close), onPressed: _saving ? null : () => Navigator.pop(context, false)),
          title: const Row(children: [
            Icon(Icons.local_shipping_outlined, size: 20, color: TColors.blue600),
            SizedBox(width: 8),
            Flexible(child: Text('Create delivery run — load driver', overflow: TextOverflow.ellipsis)),
          ]),
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          const Text(
            'Assign a driver, pick the vehicle + route, and list the products being loaded. Stock moves out of the warehouse on save.',
            style: TextStyle(fontSize: 13, color: TColors.slate500),
          ),
          const SizedBox(height: 12),
          formSection('Driver & route', _indigo, [
            _field(
              'Driver *',
              AppSelect<int>(
                value: _driver == 0 ? null : _driver,
                hintText: 'Pick driver',
                items: [
                  for (final d in widget.drivers)
                    if (d['isActive'] == true) AppSelectItem(value: tIntOrNull(d['poultryDriverId']) ?? 0, label: tStr(d['driverName'])),
                ],
                onChanged: (v) => setState(() {
                  _driver = v ?? 0;
                  final d = widget.drivers.where((x) => tIntOrNull(x['poultryDriverId']) == _driver).firstOrNull;
                  _vehicle = tIntOrNull(d?['defaultVehicleId']) ?? _vehicle;
                }),
              ),
            ),
            _field(
              'Vehicle *',
              AppSelect<int>(
                value: _vehicle == 0 ? null : _vehicle,
                hintText: 'Pick vehicle',
                items: [
                  for (final v in widget.vehicles)
                    if (v['status'] == 'Active')
                      AppSelectItem(
                        value: tIntOrNull(v['poultryVehicleId']) ?? 0,
                        label: '${tStr(v['vehicleName'])}${tStr(v['vehicleType']).isNotEmpty ? ' (${tStr(v['vehicleType'])})' : ''}',
                      ),
                ],
                onChanged: (v) => setState(() => _vehicle = v ?? 0),
              ),
            ),
            _field(
              'Route',
              AppSelect<int>(
                value: _route == 0 ? null : _route,
                hintText: 'Pick route',
                items: [for (final r in widget.routes) AppSelectItem(value: tIntOrNull(r['poultryRouteId']) ?? 0, label: tStr(r['routeName']))],
                onChanged: (v) => setState(() {
                  _route = v ?? 0;
                  final r = widget.routes.where((x) => tIntOrNull(x['poultryRouteId']) == _route).firstOrNull;
                  if (_vehicle == 0) _vehicle = tIntOrNull(r?['defaultVehicleId']) ?? _vehicle;
                }),
              ),
            ),
            _field(
              'Opening cash with driver',
              NumBox(value: _openingCash, decimal: true, onChanged: (v) => setState(() => _openingCash = v)),
              info: 'Cash float given to the driver before departure — change, fuel and small expenses. Separate from the cash they collect from sales.',
            ),
            _field(
              'Load date',
              AppDateField(
                value: DateTime.tryParse(_date),
                onChanged: (v) => setState(() => _date = v == null ? '' : v.toIso8601String().substring(0, 10)),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                color: _amber,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Row(children: [
                  const Expanded(child: Text('Products loaded', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white))),
                  FilledButton.tonalIcon(onPressed: _add, icon: const Icon(Icons.add, size: 16), label: const Text('Add product')),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('One row per product on this run.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                  const SizedBox(height: 8),
                  if (_items.isEmpty)
                    const Text('No products. Click "Add product" to add one.', style: TextStyle(fontSize: 12, color: TColors.slate500))
                  else
                    for (var i = 0; i < _items.length; i++) _loadCard(i, fmt),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          formSection('Notes', _slate, [_field('Notes', AppInput(controller: _notes, minLines: 3, maxLines: 5))]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Expanded(child: Text('Total expected cash:', style: TextStyle(fontSize: 14, color: TColors.slate500))),
              Text(fmt(total), style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Load & approve'),
          ),
          const SizedBox(height: 8),
          SizedBox(height: 44, child: redCancelButton(_saving ? null : () => Navigator.pop(context, false))),
        ]),
      ),
    );
  }

  Widget _loadCard(int i, FarmMoney fmt) {
    final it = _items[i];
    return Container(
      key: ValueKey('load-${_keys[i]}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: AppSelect<int>(
              value: it.productId == 0 ? null : it.productId,
              hintText: 'Pick product',
              items: _productItems,
              onChanged: (v) => setState(() {
                it.productId = v ?? 0;
                final p = widget.products.where((x) => tIntOrNull(x['poultryProductId']) == it.productId).firstOrNull;
                if (p?['unitPrice'] != null) it.unitPrice = tNum(p!['unitPrice']);
              }),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600),
            onPressed: () => setState(() {
              _items.removeAt(i);
              _keys.removeAt(i);
            }),
          ),
        ]),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 8) / 2;
          return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.end, children: [
            SizedBox(width: w, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('Qty (crates)'),
              NumBox(value: it.crates, onChanged: (v) => setState(() => it.crates = v)),
            ])),
            SizedBox(width: w, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('Eggs / crate',
                  info: 'How many eggs are in one crate — used to convert the crates above into the egg count that leaves stock. '
                      'Only applies to egg products; birds and other goods move one unit per crate whatever this says.'),
              NumBox(value: it.eggsPerCrate, onChanged: (v) => setState(() => it.eggsPerCrate = v)),
            ])),
            SizedBox(width: w, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('Unit price'),
              NumBox(value: it.unitPrice, decimal: true, onChanged: (v) => setState(() => it.unitPrice = v)),
            ])),
            SizedBox(width: w, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _label('Expected'),
              Text(fmt(it.crates * it.unitPrice), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ])),
          ]);
        }),
      ]),
    );
  }
}

// ------------------------------------------------------------ Record driver return

/// What the return dialog opens on: a fresh return, or a saved one to edit.
class ReturnSeed {
  ReturnSeed({
    required this.loading,
    required this.items,
    required this.payments,
    required this.date,
    this.notes = '',
    this.detailed = false,
    this.breakdown = const [],
    this.expenses = const [],
    this.editing,
  });
  final Map loading;
  final List<ReturnItem> items;
  final ReturnPayments payments;
  final String date, notes;
  final bool detailed;
  final List<BreakdownRow> breakdown;
  final List<ExpenseRow> expenses;

  /// The return being edited: cancelled before the new one is saved, deleted after.
  final Map? editing;
}

class DriverReturnDialog extends StatefulWidget {
  const DriverReturnDialog({super.key, required this.session, required this.company, required this.seed, required this.products, required this.money});
  final Session session;
  final Company company;
  final ReturnSeed seed;
  final List<Map> products;
  final FarmMoney money;
  @override
  State<DriverReturnDialog> createState() => _DriverReturnDialogState();
}

class _DriverReturnDialogState extends State<DriverReturnDialog> {
  late final List<ReturnItem> _items = widget.seed.items;
  late final ReturnPayments _pay = widget.seed.payments;
  late String _date = widget.seed.date;
  late final _notes = TextEditingController(text: widget.seed.notes);
  late bool _detailed = widget.seed.detailed;
  late final List<BreakdownRow> _breakdown = [...widget.seed.breakdown];
  late final List<ExpenseRow> _expenses = [...widget.seed.expenses];
  late bool _breakdownOpen = widget.seed.detailed && widget.seed.breakdown.isNotEmpty;
  late bool _expensesOpen = widget.seed.expenses.isNotEmpty;
  bool _override = false, _saving = false;
  int _seed = 0;
  late final List<int> _rowKeys = [for (final _ in _breakdown) _seed++];
  late final List<int> _expKeys = [for (final _ in _expenses) _seed++];

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  String get _userId => widget.session.tokens.userId ?? '';
  FarmMoney get _fmt => widget.money;
  Map get _l => widget.seed.loading;

  ReturnCalc get _calc => ReturnCalc(items: _items, pay: _pay, breakdown: _breakdown, expenses: _expenses, detailed: _detailed, loading: _l);

  void _set(VoidCallback f) => setState(() {
        f();
        // Summary posting is unavailable while there are credit sales.
        if (!_detailed && _pay.credit > 0) _detailed = true;
      });

  Future<void> _save({bool approve = false}) async {
    if (_saving) return;
    final c = _calc;
    final p = c.problem(override: _override);
    if (p != null) {
      trackerToast(context, p.$1, description: p.$2, error: true);
      return;
    }
    setState(() => _saving = true);
    final edited = widget.seed.editing;
    try {
      if (edited != null) {
        try {
          await _api.post('/api/Poultry/driver-returns/${edited['poultryDriverReturnId']}/cancel', query: {'farmId': _farmId});
        } on ApiException {
          // best effort
        }
      }
      final body = {
        ...c.body(loadingId: tIntOrNull(_l['poultryVehicleLoadingId']) ?? 0, returnDate: dayToIso(_date), notes: _notes.text),
        'farmId': _farmId,
        'createdBy': _userId,
      };
      await _api.post(approve ? '/api/Poultry/driver-returns/approve-reconcile' : '/api/Poultry/driver-returns', body: body);
      if (edited != null) {
        try {
          await _api.delete('/api/Poultry/driver-returns/${edited['poultryDriverReturnId']}?farmId=${Uri.encodeQueryComponent(_farmId)}');
        } on ApiException {
          // could not remove the replaced return
        }
      }
      if (!mounted) return;
      trackerToast(
        context,
        approve ? 'Return reconciled' : (edited != null ? 'Edited return saved as Draft' : 'Return recorded as Draft'),
        description: approve
            ? 'Sales, payments, inventory and customer balances updated.'
            : "Approve from the Returns tab when you're ready to reconcile.",
      );
      Navigator.pop(context, true);
      return;
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Return failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  List<AppSelectItem<int>> get _productItems =>
      [for (final p in widget.products) AppSelectItem(value: tIntOrNull(p['poultryProductId']) ?? 0, label: tStr(p['name']))];

  Widget _fig(String label, String value, {Color? color}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color ?? TColors.slate900)),
      ]);

  Widget _grid(List<Widget> cells) => LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - 12) / 2;
        return Wrap(spacing: 12, runSpacing: 10, children: [for (final x in cells) SizedBox(width: w, child: x)]);
      });

  Widget _numRow(String label, Widget box, {String? hint, double width = 130}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
              if (hint != null) Text(hint, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
            ]),
          ),
          const SizedBox(width: 10),
          SizedBox(width: width, child: box),
        ]),
      );

  Widget _box(Color border, Color bg, Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final c = _calc;
    final fmt = _fmt;
    final title = 'Record driver return — ${tStr(_l['driverName']).isEmpty ? '—' : tStr(_l['driverName'])} / '
        '${tStr(_l['vehicleName'])} / ${tStr(_l['routeName']).isEmpty ? '—' : tStr(_l['routeName'])}';
    final ok = c.cratesOk;
    final collectedColor = c.shortage > 0 ? TColors.rose600 : c.overage > 0 ? TColors.green700 : TColors.slate900;

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.close), onPressed: _saving ? null : () => Navigator.pop(context, false)),
          title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          const Text(
            'Reconcile crates sold / returned / damaged per product, then enter the payment summary. Optionally add the per-customer breakdown and delivery expenses.',
            style: TextStyle(fontSize: 13, color: TColors.slate500),
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Return date', style: TextStyle(fontSize: 14, color: TColors.slate600)),
            const SizedBox(width: 8),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: AppDateField(
                  value: DateTime.tryParse(_date),
                  onChanged: (v) => setState(() => _date = v == null ? '' : v.toIso8601String().substring(0, 10)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _box(TColors.slate200, TColors.slate50, Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _grid([
              _fig('Loaded', '${jsNum(c.loaded)} crates'),
              _fig('Accounted', '${jsNum(c.accounted)} / ${jsNum(c.loaded)}', color: ok ? TColors.emerald700 : TColors.amber700),
              _fig('Expected cash', fmt(c.expectedCash)),
              _fig('Collected', fmt(c.collected), color: collectedColor),
            ]),
            if (c.shortage > 0 || c.overage > 0) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 16, runSpacing: 4, children: [
                if (c.shortage > 0) _kv('Shortage: ', fmt(c.shortage), TColors.rose600),
                if (c.overage > 0) _kv('Overage: ', fmt(c.overage), TColors.green700),
                if (c.expensesTotal > 0) _kv('Approved expenses: ', fmt(c.expensesTotal), TColors.slate900),
              ]),
            ],
          ])),
          const SizedBox(height: 12),
          _step1(fmt),
          const SizedBox(height: 12),
          _step2(c, fmt),
          const SizedBox(height: 12),
          _posting(),
          if (_detailed) ...[const SizedBox(height: 12), _breakdownPanel(c, fmt)],
          const SizedBox(height: 12),
          _expensesPanel(c, fmt),
          const SizedBox(height: 12),
          formSection('Notes', _slate, [_field('Notes', AppInput(controller: _notes, minLines: 3, maxLines: 5))]),
          const SizedBox(height: 12),
          _box(
            ok ? TColors.emerald200 : TColors.rose200,
            ok ? TColors.emerald50 : TColors.rose50,
            Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.spaceBetween, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: 'Sold ${jsNum(c.sold)} + Returned ${jsNum(c.returned)} + Damaged ${jsNum(c.damaged)} = '),
                TextSpan(text: jsNum(c.accounted), style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: ' of Loaded '),
                TextSpan(text: jsNum(c.loaded), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]), style: TextStyle(fontSize: 14, color: ok ? TColors.emerald800 : TColors.rose800)),
              Text(ok ? '✓ Crates balanced' : "✗ Crates don't balance",
                  style: TextStyle(fontWeight: FontWeight.w600, color: ok ? TColors.emerald800 : TColors.rose800)),
            ]),
          ),
          if (c.creditWithoutCustomer) ...[
            const SizedBox(height: 8),
            _box(TColors.amber200, TColors.amber50, const Text(
              'Credit sales are not assigned to customers. Customer balances will not be accurate unless credit is linked via the breakdown.',
              style: TextStyle(fontSize: 12, color: TColors.amber800),
            )),
          ],
          if (c.detailedCreditUnassigned) ...[
            const SizedBox(height: 8),
            _box(TColors.rose200, TColors.rose50, const Text(
              'One or more customer rows have credit but no customer label. Add a label or tick the admin override below.',
              style: TextStyle(fontSize: 12, color: TColors.rose800),
            )),
          ],
          if ((_detailed && c.breakdownProvided && !c.breakdownBalanced) || c.detailedCreditUnassigned)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: _override,
              onChanged: (v) => setState(() => _override = v ?? false),
              title: const Text('Admin override — approve anyway', style: TextStyle(fontSize: 12)),
            ),
          const SizedBox(height: 8),
          _box(
            c.shortage > 0 ? TColors.rose200 : c.overage > 0 ? TColors.amber200 : TColors.slate200,
            c.shortage > 0 ? TColors.rose50 : c.overage > 0 ? TColors.amber50 : TColors.slate50,
            _grid([
              _fig('Expected cash', fmt(c.expectedCash)),
              _fig('Collected', fmt(c.collected)),
              _fig('Shortage', fmt(c.shortage), color: c.shortage > 0 ? TColors.rose600 : TColors.slate400),
              _fig('Overage', fmt(c.overage), color: c.overage > 0 ? TColors.green700 : TColors.slate400),
              _fig('Approved expenses', fmt(c.expensesTotal)),
            ]),
          ),
          if (!ok) ...[
            const SizedBox(height: 8),
            _box(TColors.amber200, TColors.amber50, const Text(
              "Approve & Reconcile is disabled because the crate counts don't reconcile yet (each product's Sold + Returned + Damaged must equal Loaded).",
              style: TextStyle(fontSize: 12, color: TColors.amber800),
            )),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Tooltip(
                message: !ok ? 'Reconcile per-product crates before saving' : 'Saves as Draft; approve from the Returns tab',
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), padding: const EdgeInsets.symmetric(horizontal: 8)),
                  onPressed: _saving || !ok ? null : () => _save(),
                  child: Text(_saving ? 'Saving…' : 'Record return (Draft)', textAlign: TextAlign.center),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48), backgroundColor: TColors.emerald600, padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: _saving || !ok ? null : () => _save(approve: true),
                child: Text(_saving ? 'Working…' : 'Approve & Reconcile', textAlign: TextAlign.center),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          SizedBox(height: 44, child: redCancelButton(_saving ? null : () => Navigator.pop(context, false))),
        ]),
      ),
    );
  }

  Widget _kv(String k, String v, Color color) => Text.rich(TextSpan(children: [
        TextSpan(text: k),
        TextSpan(text: v, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
      ]), style: const TextStyle(fontSize: 12, color: TColors.slate600));

  Widget _step1(FarmMoney fmt) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: _amber,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Step 1 · Reconcile crates per product', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
              Text('Sold + Returned + Damaged must equal Loaded', style: TextStyle(fontSize: 12, color: Color(0xFFFFFBEB))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < _items.length; i++) _returnItem(i, fmt),
            ]),
          ),
        ]),
      );

  Widget _returnItem(int i, FarmMoney fmt) {
    final it = _items[i];
    final diff = it.accounted - it.loaded;
    return Container(
      key: ValueKey('ret-$i-${it.productId}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: it.balanced ? Colors.white : TColors.amber50,
        border: Border.all(color: it.balanced ? TColors.slate200 : TColors.amber300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(it.productName, style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900))),
          Text(it.balanced ? '✓ Balanced' : (diff > 0 ? '+${jsNum(diff)}' : jsNum(diff)),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: it.balanced ? TColors.emerald600 : TColors.amber700)),
        ]),
        const SizedBox(height: 10),
        _numRow('Loaded (crates)', Text(jsNum(it.loaded), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w500))),
        _numRow('Expected', Text(fmt(it.sold * it.unitPrice), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
        _numRow('Sold (crates)', NumBox(value: it.sold, onChanged: (v) => _set(() => it.sold = v))),
        _numRow('Unit price', NumBox(value: it.unitPrice, decimal: true, onChanged: (v) => _set(() => it.unitPrice = v))),
        _numRow('Returned (crates)', NumBox(value: it.returned, onChanged: (v) => _set(() => it.returned = v))),
        _numRow('Damaged (crates)', NumBox(value: it.damaged, onChanged: (v) => _set(() => it.damaged = v))),
      ]),
    );
  }

  Widget _step2(ReturnCalc c, FarmMoney fmt) => formSection('Step 2 · Money collected', _green, [
        _numRow('Cash', NumBox(value: _pay.cash, decimal: true, onChanged: (v) => _set(() => _pay.cash = v)),
            hint: 'Physical cash the driver collected on the run.'),
        _numRow('MoMo', NumBox(value: _pay.momo, decimal: true, onChanged: (v) => _set(() => _pay.momo = v)),
            hint: 'Mobile Money (MTN, Vodafone, AirtelTigo).'),
        _numRow('Bank', NumBox(value: _pay.bank, decimal: true, onChanged: (v) => _set(() => _pay.bank = v)),
            hint: 'Bank transfers / cheque deposits received today.'),
        _numRow('Credit sales', NumBox(value: _pay.credit, decimal: true, onChanged: (v) => _set(() => _pay.credit = v)),
            hint: 'Goods given on credit — to be paid later.'),
        _box(TColors.slate50, TColors.slate50, Row(children: [
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Unaccounted cash', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
              Text('Expected sales minus everything collected (cash + MoMo + bank + credit).',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: TColors.slate500)),
            ]),
          ),
          Text(
            c.shortage > 0 ? fmt(c.shortage) : c.overage > 0 ? '+${fmt(c.overage)} over' : fmt(0),
            style: TextStyle(
                fontWeight: FontWeight.w600, color: c.shortage > 0 ? TColors.rose600 : c.overage > 0 ? TColors.amber600 : TColors.slate700),
          ),
        ])),
        if (!c.floatBalanced) ...[
          const SizedBox(height: 8),
          _box(TColors.rose200, TColors.rose50, Text(
            "Cash returned (${fmt(_pay.floatBack)}) doesn't match the expected float of ${fmt(c.expectedFloatBack)}"
            '${c.expensesTotal > 0 ? ' (opening ${fmt(c.openingFloat)} − approved expenses ${fmt(c.expensesTotal)})' : ' (opening cash ${fmt(c.openingFloat)})'}. '
            'You can still save as Draft, but Approve & Reconcile is blocked until it balances.',
            style: const TextStyle(fontSize: 12, color: TColors.rose800),
          )),
        ],
        const Divider(height: 24),
        _numRow('Cash returned by driver', NumBox(value: _pay.floatBack, decimal: true, onChanged: (v) => _set(() => _pay.floatBack = v)),
            hint: "The driver's float coming back (opening cash, minus any approved cash expenses). Not a sale.", width: 150),
      ]);

  Widget _posting() {
    final credit = _pay.credit > 0;
    return formSection('How should this delivery sale be posted?', _purple, [
      RadioGroup<bool>(
        groupValue: _detailed,
        onChanged: (v) {
          if (v == false && credit) return;
          setState(() => _detailed = v ?? _detailed);
        },
        child: Column(children: [
          Opacity(
            opacity: credit ? .5 : 1,
            child: RadioListTile<bool>(
              contentPadding: EdgeInsets.zero,
              value: false,
              enabled: !credit,
              title: const Text('Summary only', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("Posts to the company's General Delivery Customer. No per-shop tracking.", style: TextStyle(fontSize: 13)),
                if (credit)
                  const Text('Unavailable while there are credit sales — use the detailed breakdown.',
                      style: TextStyle(fontSize: 13, color: TColors.amber700)),
              ]),
            ),
          ),
          const RadioListTile<bool>(
            contentPadding: EdgeInsets.zero,
            value: true,
            title: Text('Detailed customer breakdown', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text(
              'Record real customer/shop sales one-by-one (free-text names for walk-ins). The breakdown appears right below when selected.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _collapsible({required bool open, required VoidCallback onToggle, required String title, required String hint, required String trailing, required Widget body}) =>
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Material(
            color: TColors.slate50,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                      TextSpan(text: ' $hint', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                    ])),
                  ),
                  const SizedBox(width: 6),
                  Text(trailing, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                ]),
              ),
            ),
          ),
          if (open) Padding(padding: const EdgeInsets.all(12), child: body),
        ]),
      );

  Widget _breakdownPanel(ReturnCalc c, FarmMoney fmt) => _collapsible(
        open: _breakdownOpen,
        onToggle: () => setState(() => _breakdownOpen = !_breakdownOpen),
        title: 'Customer sales breakdown',
        hint: '— record each customer/shop sale; posts to Sales + Payments on approve',
        trailing: '${_breakdown.length} customer${_breakdown.length == 1 ? '' : 's'}',
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _breakdown.add(BreakdownRow());
                _rowKeys.add(_seed++);
              }),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add customer sale'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _breakdown.clear();
                _rowKeys.clear();
                _breakdownOpen = false;
              }),
              child: const Text('Use summary only'),
            ),
          ]),
          const SizedBox(height: 8),
          for (var i = 0; i < _breakdown.length; i++) _customerRow(i, fmt),
          if (_breakdown.isNotEmpty)
            _box(
              c.breakdownBalanced ? TColors.emerald200 : TColors.amber200,
              c.breakdownBalanced ? TColors.emerald50 : TColors.amber50,
              c.breakdownBalanced
                  ? const Text('✓ Customer breakdown matches the return summary.', style: TextStyle(fontSize: 12, color: TColors.emerald800))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Customer breakdown does not match the return summary.', style: TextStyle(fontSize: 12, color: TColors.amber800)),
                      if (!c.paymentsBalance)
                        Text(
                          'Cash ${fmt(c.bCash)} vs ${fmt(_pay.cash)} · MoMo ${fmt(c.bMomo)} vs ${fmt(_pay.momo)} · '
                          'Bank ${fmt(c.bBank)} vs ${fmt(_pay.bank)} · Credit ${fmt(c.bCredit)} vs ${fmt(_pay.credit)}',
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: TColors.amber800),
                        ),
                      if (!c.qtyBalance)
                        const Text("Per-product quantities don't match Sold totals.", style: TextStyle(fontSize: 12, color: TColors.amber800)),
                    ]),
            ),
        ]),
      );

  Widget _customerRow(int i, FarmMoney fmt) {
    final r = _breakdown[i];
    Widget small(String label, Widget box) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_label(label), box]);
    return Container(
      key: ValueKey('cust-${_rowKeys[i]}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Customer ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14))),
          IconButton(
            tooltip: 'Remove customer',
            icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600),
            onPressed: () => setState(() {
              _breakdown.removeAt(i);
              _rowKeys.removeAt(i);
            }),
          ),
        ]),
        _field('Customer / shop name', AppInput(initialValue: r.label, hintText: 'Walk-in / shop name', onChanged: (v) => setState(() => r.label = v))),
        _field('Notes', AppInput(initialValue: r.notes, hintText: 'Optional', onChanged: (v) => r.notes = v)),
        Container(
          decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: TColors.slate50,
              padding: const EdgeInsets.only(left: 8),
              child: Row(children: [
                const Expanded(child: Text('Items sold to this customer', style: TextStyle(fontSize: 12))),
                TextButton.icon(
                  onPressed: widget.products.isEmpty
                      ? null
                      : () => setState(() => r.items.add(BreakdownItem(tIntOrNull(widget.products.first['poultryProductId']) ?? 0,
                          unitPrice: tNum(widget.products.first['unitPrice'])))),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Add item'),
                ),
              ]),
            ),
            if (r.items.isEmpty)
              const Padding(padding: EdgeInsets.all(10), child: Text('No items yet.', style: TextStyle(fontSize: 12, color: TColors.slate500)))
            else
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(children: [
                  for (var j = 0; j < r.items.length; j++)
                    Container(
                      key: ValueKey('cust-${_rowKeys[i]}-item-$j-${r.items.length}'),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
                      child: Column(children: [
                        Row(children: [
                          Expanded(
                            child: AppSelect<int>(
                              value: r.items[j].productId == 0 ? null : r.items[j].productId,
                              items: _productItems,
                              onChanged: (v) => setState(() {
                                final it = r.items[j];
                                it.productId = v ?? 0;
                                final p = widget.products.where((x) => tIntOrNull(x['poultryProductId']) == it.productId).firstOrNull;
                                if (p?['unitPrice'] != null) it.unitPrice = tNum(p!['unitPrice']);
                              }),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove item',
                            icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600),
                            onPressed: () => setState(() => r.items.removeAt(j)),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Expanded(child: small('Qty (crates)', NumBox(value: r.items[j].quantity, onChanged: (v) => setState(() => r.items[j].quantity = v)))),
                          const SizedBox(width: 6),
                          Expanded(
                              child: small('Price', NumBox(value: r.items[j].unitPrice, decimal: true, onChanged: (v) => setState(() => r.items[j].unitPrice = v)))),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              _label('Total'),
                              Text(fmt(r.items[j].quantity * r.items[j].unitPrice), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            ]),
                          ),
                        ]),
                      ]),
                    ),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, cst) {
          final w = (cst.maxWidth - 8) / 2;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(width: w, child: small('Cash paid', NumBox(value: r.cash, decimal: true, onChanged: (v) => setState(() => r.cash = v)))),
            SizedBox(width: w, child: small('MoMo paid', NumBox(value: r.momo, decimal: true, onChanged: (v) => setState(() => r.momo = v)))),
            SizedBox(width: w, child: small('Bank paid', NumBox(value: r.bank, decimal: true, onChanged: (v) => setState(() => r.bank = v)))),
            SizedBox(width: w, child: small('Credit', NumBox(value: r.credit, decimal: true, onChanged: (v) => setState(() => r.credit = v)))),
          ]);
        }),
        const SizedBox(height: 6),
        DefaultTextStyle.merge(
          style: TextStyle(fontSize: 12, color: r.mismatch ? TColors.amber700 : TColors.slate500),
          child: Row(children: [
            Expanded(child: Text.rich(TextSpan(children: [
              const TextSpan(text: 'Items total: '),
              TextSpan(text: fmt(r.lineTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]))),
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Payments + credit: '),
              TextSpan(text: fmt(r.paidPlusCredit), style: const TextStyle(fontWeight: FontWeight.w700)),
            ])),
          ]),
        ),
      ]),
    );
  }

  Widget _expensesPanel(ReturnCalc c, FarmMoney fmt) => _collapsible(
        open: _expensesOpen,
        onToggle: () => setState(() => _expensesOpen = !_expensesOpen),
        title: 'Step 4 · Delivery expenses',
        hint: '— fuel, toll, loading boys, etc.',
        trailing: fmt(c.expensesTotal),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => setState(() {
                _expenses.add(ExpenseRow());
                _expKeys.add(_seed++);
              }),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add expense'),
            ),
          ),
          const SizedBox(height: 8),
          if (_expenses.isEmpty)
            const Text('No expenses logged.', style: TextStyle(fontSize: 12, color: TColors.slate500))
          else
            for (var i = 0; i < _expenses.length; i++) _expenseRow(i),
        ]),
      );

  Widget _expenseRow(int i) {
    final e = _expenses[i];
    return Container(
      key: ValueKey('exp-${_expKeys[i]}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('Category'),
              AppSelect<String>(
                value: e.category,
                items: [for (final cat in deliveryExpenseCategories) AppSelectItem(value: cat, label: prettyCategory(cat))],
                onChanged: (v) => setState(() => e.category = v ?? e.category),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('Amount'),
              NumBox(value: e.amount, decimal: true, onChanged: (v) => _set(() => e.amount = v)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        _label('Description'),
        AppInput(initialValue: e.description, onChanged: (v) => e.description = v),
        const SizedBox(height: 4),
        Row(children: [
          Checkbox(value: e.approved, onChanged: (v) => _set(() => e.approved = v ?? false)),
          const Expanded(child: Text('Approved', style: TextStyle(fontSize: 14, color: TColors.slate700))),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: TColors.red200)),
            onPressed: () => setState(() {
              _expenses.removeAt(i);
              _expKeys.removeAt(i);
            }),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Remove'),
          ),
        ]),
      ]),
    );
  }
}

/// openReturnDlg / prefillFromExistingReturn: builds what the dialog opens on.
/// Returns null (after a toast) when the delivery is already reconciled.
Future<ReturnSeed?> buildReturnSeed(
  BuildContext context, {
  required ApiClient api,
  required String farmId,
  required Map loading,
  required List<Map> returns,
  required List<Map> products,
  Map? existing,
}) async {
  final lid = tIntOrNull(loading['poultryVehicleLoadingId']) ?? 0;
  final q = {'farmId': farmId};
  String name(Object? n, Object? id, String fallback) =>
      tStr(n).isNotEmpty ? tStr(n) : (_productName(products, tIntOrNull(id) ?? 0).isNotEmpty ? _productName(products, tIntOrNull(id) ?? 0) : fallback);

  Future<ReturnSeed> fresh() async {
    var items = <ReturnItem>[];
    try {
      final rows = rowsOf(await api.get('/api/Poultry/vehicle-loadings/$lid/items', query: q));
      items = rows.isNotEmpty
          ? [
              for (final it in rows)
                ReturnItem(
                  productId: tIntOrNull(it['poultryProductId']) ?? 0,
                  productName: name(it['productName'], it['poultryProductId'], 'Product #${tStr(it['poultryProductId'])}'),
                  loaded: tNum(it['cratesLoaded']),
                  sold: tNum(it['cratesLoaded']),
                  unitPrice: tNum(it['unitPrice']),
                ),
            ]
          : [
              ReturnItem(
                productId: tIntOrNull(loading['poultryProductId']) ?? 0,
                productName: name(loading['productName'], loading['poultryProductId'], 'Product'),
                loaded: tNum(loading['cratesLoaded']),
                sold: tNum(loading['cratesLoaded']),
                unitPrice: tNum(loading['expectedSellingPricePerCrate']),
              ),
            ];
    } on ApiException {
      items = [];
    }
    return ReturnSeed(
      loading: loading,
      items: items,
      payments: ReturnPayments()..floatBack = tNum(loading['openingCashWithDriver']),
      date: _dayOf(loading['loadDate']),
    );
  }

  if (existing == null) {
    final open = returns.where((r) => tIntOrNull(r['poultryVehicleLoadingId']) == lid && tStr(r['status']) != 'Cancelled').firstOrNull;
    if (open != null) {
      if (tStr(open['status']) == 'Draft') {
        trackerToast(context, "Continuing this delivery's draft return", description: 'Edit the figures and Approve & Reconcile when ready.');
        existing = open;
      } else {
        trackerToast(context, 'This delivery is already reconciled', description: 'Reverse it from the Reconciled tab to make changes.', error: true);
        return null;
      }
    } else {
      return fresh();
    }
  }

  final r = existing;
  final rid = tStr(r['poultryDriverReturnId']);
  final detailed = tStr(r['salesPostingMode']) == 'Detailed';
  final pay = ReturnPayments()
    ..cash = tNum(r['cashCollected'])
    ..momo = tNum(r['moMoCollected'])
    ..bank = tNum(r['bankCollected'])
    ..credit = tNum(r['creditSalesAmount'])
    ..floatBack = r['cashReturnedByDriver'] != null ? tNum(r['cashReturnedByDriver']) : tNum(loading['openingCashWithDriver']);
  try {
    final res = await Future.wait([
      api.get('/api/Poultry/driver-returns/$rid/items', query: q).then(rowsOf),
      api.get('/api/Poultry/driver-returns/$rid/customer-sales', query: q).then(rowsOf).catchError((_) => <Map>[]),
      api.get('/api/Poultry/driver-returns/$rid/expenses', query: q).then(rowsOf).catchError((_) => <Map>[]),
    ]);
    final items = res[0].isNotEmpty
        ? [
            for (final it in res[0])
              ReturnItem(
                productId: tIntOrNull(it['poultryProductId']) ?? 0,
                productName: name(it['productName'], it['poultryProductId'], 'Product #${tStr(it['poultryProductId'])}'),
                loaded: tNum(it['cratesLoaded']),
                sold: tNum(it['cratesSold']),
                returned: tNum(it['cratesReturned']),
                damaged: tNum(it['cratesDamaged']),
                unitPrice: tNum(it['unitPrice']),
              ),
          ]
        : (await fresh()).items;
    return ReturnSeed(
      loading: loading,
      items: items,
      payments: pay,
      date: _dayOf(r['returnDate']),
      notes: tStr(r['notes']),
      detailed: detailed,
      breakdown: [
        for (final cs in res[1])
          BreakdownRow(
            customerId: tIntOrNull(cs['customerId']),
            label: tStr(cs['customerLabel']),
            cash: tNum(cs['cashPaid']),
            momo: tNum(cs['moMoPaid']),
            bank: tNum(cs['bankPaid']),
            credit: tNum(cs['creditAmount']),
            notes: tStr(cs['notes']),
          ),
      ],
      expenses: [
        for (final e in res[2])
          ExpenseRow(
            category: tStr(e['expenseCategory']),
            amount: tNum(e['amount']),
            description: tStr(e['description']),
            approved: e['isApproved'] != false,
          ),
      ],
      editing: r,
    );
  } on ApiException {
    return fresh();
  }
}

String _dayOf(Object? iso) {
  final s = tStr(iso);
  return s.length >= 10 ? s.substring(0, 10) : _today();
}
