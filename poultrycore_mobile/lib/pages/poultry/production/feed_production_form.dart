// The feed production batch form (components/feed-production/batch-form.tsx)
// with the formula scaling from lib/feed-formula-scale.ts: the finished feed
// output, the ingredient lines (formula-driven or a typed recipe scaled to
// the batch), additional costs, the three impact cards, Save Draft and
// Save & Post.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../shared/business_dates.dart';
import '../money/money_widgets.dart' show formSection;
import '../purchase/raw_material_dialogs.dart' show RawPurchaseDialog;
import '../reports/report_format.dart' show FarmMoney;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, loc, jsNum;
import '../trackers/tracker_widgets.dart';

// ------------------------------------------------------------ feed-formula-scale

num roundQty(num n) => double.parse(n.toStringAsFixed(3));

/// A recipe line: a formula line, or a typed quantity read as one.
class RecipeLine {
  const RecipeLine(this.id, this.percentageMode, this.percentage, this.fixedQuantity);
  final int id;
  final bool percentageMode;
  final num percentage, fixedQuantity;
  RecipeLine withId(int i) => RecipeLine(i, percentageMode, percentage, fixedQuantity);

  static RecipeLine fromFormula(Map fl) => RecipeLine(tIntOrNull(fl['poultryFeedFormulaLineId']) ?? 0, tStr(fl['quantityMode']) == 'Percentage',
      tNum(fl['percentage']), tNum(fl['fixedQuantity']));
}

({num pctTotal, num fixedBase, String shape}) formulaCoverage(List<RecipeLine> ls) {
  final pct = [for (final l in ls) if (l.percentageMode) l];
  final fixed = [for (final l in ls) if (!l.percentageMode) l];
  return (
    pctTotal: pct.fold<num>(0, (s, l) => s + l.percentage),
    fixedBase: fixed.fold<num>(0, (s, l) => s + l.fixedQuantity),
    shape: ls.isEmpty
        ? 'empty'
        : pct.isNotEmpty && fixed.isNotEmpty
            ? 'mixed'
            : pct.isNotEmpty
                ? 'percentage'
                : 'fixed',
  );
}

Map<int, num> formulaUnitFactors(List<RecipeLine> ls) {
  final c = formulaCoverage(ls);
  final fixedShare = c.shape == 'fixed' ? 1 : (100 - c.pctTotal) / 100;
  return {
    for (final l in ls)
      if (l.percentageMode)
        l.id: l.percentage / 100
      else if (c.fixedBase > 0 && fixedShare > 0)
        l.id: fixedShare * l.fixedQuantity / c.fixedBase,
  };
}

Map<int, num> scaleFormulaLines(List<RecipeLine> ls, num q) {
  if (q <= 0) return {for (final l in ls) l.id: 0};
  final c = formulaCoverage(ls);
  final remainder = c.shape == 'fixed' ? q : q * ((100 - c.pctTotal) / 100);
  final canScale = c.fixedBase > 0 && remainder > 0;
  final scale = canScale ? remainder / c.fixedBase : 0;
  return {
    for (final l in ls) l.id: roundQty(l.percentageMode ? q * l.percentage / 100 : (canScale ? l.fixedQuantity * scale : l.fixedQuantity)),
  };
}

// ------------------------------------------------------------ the form's model

const feedSourceTypes = [
  ('FromInventory', 'From Inventory'),
  ('BoughtDuringProduction', 'Bought During Production'),
  ('MixedSource', 'Mixed Source'),
];
const feedCostTypes = ['Labor', 'Grinding', 'Transport', 'Electricity', 'Fuel', 'Packaging', 'MachineMaintenance', 'Other'];
String feedCostLabel(String c) => c == 'MachineMaintenance' ? 'Machine Maintenance' : c;
const feedPaymentStatuses = ['Paid', 'Unpaid', 'Partial'];

bool isFinishedFeed(Object? c) => RegExp('finish', caseSensitive: false).hasMatch(tStr(c));
bool isIngredient(Object? c) => RegExp('feed', caseSensitive: false).hasMatch(tStr(c)) && !isFinishedFeed(c);

num _n(Object? v) => v is num ? v : (num.tryParse(tStr(v)) ?? 0);

int _keySeq = 0;

class FeedLine {
  FeedLine() : key = 'l${_keySeq++}';
  final String key;
  int? ingredientItemId, formulaLineId, paidFromCashAccountId;
  bool qtyOverridden = false;
  String enteredQty = '', sourceType = 'FromInventory', quantityUsed = '', unitOfMeasure = '';
  String inventoryQuantityUsed = '', purchasedQuantityUsed = '', inventoryUnitCost = '', purchasedUnitCost = '';
  String supplierName = '', purchaseReference = '', paymentStatus = 'Unpaid', amountPaid = '', paymentMethod = 'Cash', notes = '';

  /// lineDerived.
  ({num qty, num invQty, num purQty, num invCost, num purCost, num invUnit, num purUnit, num total, num unit, num paid, num payable, bool mixedBalanced, bool hasPurchase})
      get d {
    final qty = _n(quantityUsed);
    num inv = 0, pur = 0;
    if (sourceType == 'FromInventory') {
      inv = qty;
    } else if (sourceType == 'BoughtDuringProduction') {
      pur = qty;
    } else {
      inv = _n(inventoryQuantityUsed);
      pur = _n(purchasedQuantityUsed);
    }
    final invUnit = _n(inventoryUnitCost);
    final invCost = inv * invUnit, purCost = pur * _n(purchasedUnitCost);
    final total = invCost + purCost;
    final paid = paymentStatus == 'Paid' ? purCost : (paymentStatus == 'Partial' ? _n(amountPaid) : 0);
    return (
      qty: qty,
      invQty: inv,
      purQty: pur,
      invCost: invCost,
      purCost: purCost,
      invUnit: invUnit,
      purUnit: pur > 0 ? purCost / pur : 0,
      total: total,
      unit: qty > 0 ? total / qty : 0,
      paid: paid,
      payable: math.max(0, purCost - paid),
      mixedBalanced: sourceType != 'MixedSource' || (inv + pur - qty).abs() < 0.001,
      hasPurchase: sourceType != 'FromInventory',
    );
  }

  /// splitMixed: keep a mixed line's inventory/purchase ratio at the new total.
  void splitMixed(num want) {
    if (sourceType != 'MixedSource') return;
    final inv = _n(inventoryQuantityUsed), pur = _n(purchasedQuantityUsed);
    final old = inv + pur;
    if (old <= 0) return;
    final scaled = roundQty(inv * (want / old));
    inventoryQuantityUsed = jsNum(scaled);
    purchasedQuantityUsed = jsNum(roundQty(want - scaled));
  }
}

class FeedCost {
  FeedCost() : key = 'c${_keySeq++}';
  final String key;
  String costType = 'Labor', amount = '', paymentStatus = 'Unpaid', amountPaid = '', paymentMethod = 'Cash', payeeName = '', notes = '';
  int? paidFromCashAccountId;

  ({num amount, num paid, num payable}) get d {
    final a = _n(amount);
    final paid = paymentStatus == 'Paid' ? a : (paymentStatus == 'Partial' ? _n(amountPaid) : 0);
    return (amount: a, paid: paid, payable: math.max(0, a - paid));
  }
}

/// readableError: the post endpoint's lot-shortage message, in plain words.
String readableFeedError(String raw) {
  final r = raw.trim();
  if (r.isEmpty) return 'Something went wrong.';
  final parts = [for (final p in r.split(RegExp(r'\r?\n'))) if (p.trim().isNotEmpty) p.trim()];
  if (!parts.any((p) => RegExp('tracked batch stock', caseSensitive: false).hasMatch(p))) return r;
  final items = [
    for (final p in parts)
      if (RegExp(r'for\s+"([^"]+)":\s*need\s+([\d.]+),\s*only\s+([\d.]+)', caseSensitive: false).firstMatch(p) case final m?)
        '${m[1]} (needs ${loc(num.parse(m[2]!))}, only ${loc(num.parse(m[3]!))} available)',
  ];
  return items.isNotEmpty
      ? 'Not enough ingredient stock to post: ${items.join('; ')}. Lower the quantity produced, or buy the shortfall during production.'
      : r;
}

/// A text box that shows [value] and follows it when it changes from outside.
class _Box extends StatefulWidget {
  const _Box({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  State<_Box> createState() => _BoxState();
}

class _BoxState extends State<_Box> {
  late final _c = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(_Box old) {
    super.didUpdateWidget(old);
    if (widget.value != _c.text) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppInput(
        controller: _c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: widget.onChanged,
      );
}

// ------------------------------------------------------------ the form

class FeedProductionBatchForm extends StatefulWidget {
  const FeedProductionBatchForm({super.key, required this.session, required this.company, this.existing, required this.onSaved});
  final Session session;
  final Company company;
  final Map? existing;

  /// Opens the saved batch (the web pushes /poultry-feed-production/{id}).
  final void Function(int batchId) onSaved;
  @override
  State<FeedProductionBatchForm> createState() => _FeedProductionBatchFormState();
}

class _FeedProductionBatchFormState extends State<FeedProductionBatchForm> {
  bool _loading = true, _saving = false, _posting = false, _busy = false;
  List<Map> _items = [], _formulas = [], _accounts = [], _rawItems = [];
  Map? _applied;
  FarmMoney _gh = const FarmMoney();

  int? _finishedId, _formulaId;
  late String _date = () {
    final s = tStr(widget.existing?['productionDate'] ?? DateTime.now().toUtc().toIso8601String());
    return s.length >= 10 ? s.substring(0, 10) : s;
  }();
  late String _qtyProduced = widget.existing != null ? jsNum(tNum(widget.existing!['quantityProduced'])) : '';
  late String _outputUnit = tStr(widget.existing?['outputUnit']);
  late final _batchNumber = TextEditingController(text: tStr(widget.existing?['batchNumber']));
  late final _notes = TextEditingController(text: tStr(widget.existing?['notes']));
  List<FeedLine> _lines = [];
  List<FeedCost> _costs = [];

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  String? get _userId => widget.session.tokens.userId;
  bool get _canPost => (widget.company.role ?? '').toLowerCase() != 'staff';
  Map<String, String> get _farm => {'farmId': _farmId};

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _finishedId = tIntOrNull(e?['finishedFeedItemId']);
    _formulaId = tIntOrNull(e?['formulaId']);
    final saved = [for (final l in (e?['lines'] as List? ?? const [])) if (l is Map) l];
    _lines = saved.isNotEmpty
        ? [
            for (final l in saved)
              FeedLine()
                ..ingredientItemId = tIntOrNull(l['ingredientItemId'])
                ..enteredQty = tStr(l['quantityMode']) == 'FixedQuantity' && tNum(l['fixedQuantity']) > 0 ? jsNum(tNum(l['fixedQuantity'])) : jsNum(tNum(l['quantityUsed']))
                ..sourceType = tStr(l['sourceType'])
                ..quantityUsed = jsNum(tNum(l['quantityUsed']))
                ..unitOfMeasure = tStr(l['unitOfMeasure'])
                ..inventoryQuantityUsed = l['inventoryQuantityUsed'] != null ? jsNum(tNum(l['inventoryQuantityUsed'])) : ''
                ..purchasedQuantityUsed = l['purchasedQuantityUsed'] != null ? jsNum(tNum(l['purchasedQuantityUsed'])) : ''
                ..inventoryUnitCost = l['inventoryUnitCost'] != null ? jsNum(tNum(l['inventoryUnitCost'])) : ''
                ..purchasedUnitCost = l['purchasedUnitCost'] != null ? jsNum(tNum(l['purchasedUnitCost'])) : ''
                ..supplierName = tStr(l['supplierName'])
                ..purchaseReference = tStr(l['purchaseReference'])
                ..paymentStatus = tStr(l['paymentStatus']).isNotEmpty ? tStr(l['paymentStatus']) : 'Unpaid'
                ..amountPaid = l['amountPaid'] != null ? jsNum(tNum(l['amountPaid'])) : ''
                ..paidFromCashAccountId = tIntOrNull(l['paidFromCashAccountId'])
                ..paymentMethod = tStr(l['paymentMethod']).isNotEmpty ? tStr(l['paymentMethod']) : 'Cash'
                ..notes = tStr(l['notes']),
          ]
        : [FeedLine()];
    _costs = [
      for (final c in (e?['additionalCosts'] as List? ?? const []))
        if (c is Map)
          FeedCost()
            ..costType = tStr(c['costType'])
            ..amount = jsNum(tNum(c['amount']))
            ..paymentStatus = tStr(c['paymentStatus']).isNotEmpty ? tStr(c['paymentStatus']) : 'Unpaid'
            ..amountPaid = c['amountPaid'] != null ? jsNum(tNum(c['amountPaid'])) : ''
            ..paidFromCashAccountId = tIntOrNull(c['paidFromCashAccountId'])
            ..paymentMethod = tStr(c['paymentMethod']).isNotEmpty ? tStr(c['paymentMethod']) : 'Cash'
            ..payeeName = tStr(c['payeeName'])
            ..notes = tStr(c['notes']),
    ];
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    _load();
  }

  @override
  void dispose() {
    _batchNumber.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final savedFormula = _formulaId;
      Future<List<Map>> soft(String path, Map<String, String> q) async {
        try {
          return rowsOf(await _api.get(path, query: q));
        } on ApiException {
          return <Map>[];
        }
      }

      final r = await Future.wait<Object?>([
        _api.get('/api/Poultry/feed-production/items', query: _farm),
        _api.get('/api/Poultry/feed-formulas', query: _farm),
        soft('/api/Poultry/cash-accounts', _farm),
        soft('/api/Poultry/raw-material-items', _farm),
        if (savedFormula != null) _api.get('/api/Poultry/feed-formulas/$savedFormula', query: _farm).catchError((_) => null),
      ]);
      if (!mounted) return;
      setState(() {
        _items = rowsOf(r[0]);
        _formulas = rowsOf(r[1]);
        _accounts = r[2] as List<Map>;
        _rawItems = r[3] as List<Map>;
        final full = r.length > 4 ? r[4] : null;
        final fl = full is Map ? [for (final x in (full['lines'] as List? ?? const [])) if (x is Map) x] : <Map>[];
        if (fl.isNotEmpty) {
          _relinkToFormula(fl, tNum(widget.existing?['quantityProduced']));
          _applied = full as Map;
        }
        _derive();
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to load form data', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _relinkToFormula(List<Map> formulaLines, num savedQty) {
    final required = scaleFormulaLines([for (final f in formulaLines) RecipeLine.fromFormula(f)], savedQty);
    final unclaimed = [...formulaLines];
    for (final l in _lines) {
      final idx = unclaimed.indexWhere((fl) => tIntOrNull(fl['ingredientItemId']) == l.ingredientItemId);
      if (idx < 0) continue;
      final fl = unclaimed.removeAt(idx);
      final id = tIntOrNull(fl['poultryFeedFormulaLineId']) ?? 0;
      l.formulaLineId = id;
      l.qtyOverridden = (_n(l.quantityUsed) - (required[id] ?? 0)).abs() > 0.001;
    }
  }

  Map<int, Map> get _itemById => {for (final i in _items) tIntOrNull(i['poultryRawMaterialItemId']) ?? 0: i};
  List<Map> get _finishedItems => [for (final i in _items) if (isFinishedFeed(i['category'])) i];
  List<Map> get _ingredientItems => [for (final i in _items) if (isIngredient(i['category'])) i];
  List<Map> get _activeFormulas => [for (final f in _formulas) if (f['isActive'] == true) f];
  bool get _scaling => _applied == null;
  num get _qty => _n(_qtyProduced);

  Map<int, Map> get _formulaLineById => {
        for (final fl in (_applied?['lines'] as List? ?? const []))
          if (fl is Map) tIntOrNull(fl['poultryFeedFormulaLineId']) ?? 0: fl,
      };

  /// The recipe the batch is scaled from, re-numbered by position.
  List<(String, RecipeLine)> get _recipe {
    final byId = _formulaLineById;
    final out = <(String, RecipeLine)>[];
    for (final l in _lines) {
      if (l.formulaLineId != null) {
        final fl = byId[l.formulaLineId];
        if (fl != null) out.add((l.key, RecipeLine.fromFormula(fl)));
        continue;
      }
      if (!_scaling || l.ingredientItemId == null || _n(l.enteredQty) <= 0) continue;
      out.add((l.key, RecipeLine(0, false, 0, _n(l.enteredQty))));
    }
    return [for (var i = 0; i < out.length; i++) (out[i].$1, out[i].$2.withId(i))];
  }

  String get _finishedUnit => _finishedId != null ? tStr(_itemById[_finishedId]?['unitOfMeasure']) : '';
  String get _derivedUnit => tStr(_applied?['defaultOutputUnit']).isNotEmpty ? tStr(_applied?['defaultOutputUnit']) : _finishedUnit;
  String get _unitSource => tStr(_applied?['defaultOutputUnit']).isNotEmpty
      ? 'From formula ${tStr(_applied?['formulaName'])}'
      : _finishedUnit.isNotEmpty
          ? 'From the finished feed item'
          : 'Set a unit on the formula or the finished feed item';

  /// The web's effects: follow the derived output unit, and rescale every
  /// line that is not hand-edited to the quantity produced.
  void _derive() {
    if (_derivedUnit.isNotEmpty && _derivedUnit != _outputUnit) _outputUnit = _derivedUnit;
    final recipe = _recipe;
    final required = scaleFormulaLines([for (final (_, r) in recipe) r], _qty);
    final want = {for (final (k, r) in recipe) k: required[r.id] ?? 0};
    for (final l in _lines) {
      if (l.qtyOverridden) continue;
      final w = want[l.key] ?? (l.formulaLineId == null ? roundQty(_n(l.enteredQty)) : null);
      if (w == null) continue;
      final text = w > 0 ? jsNum(w) : '';
      if (text == l.quantityUsed) continue;
      l.quantityUsed = text;
      l.splitMixed(w);
    }
  }

  void _set(VoidCallback f) => setState(() {
        f();
        _derive();
      });

  String? _shareOf(FeedLine l) {
    final entry = _recipe.where((e) => e.$1 == l.key).firstOrNull;
    if (entry == null) return null;
    final fl = entry.$2;
    if (fl.percentageMode) return '${jsNum(roundQty(fl.percentage))}% of batch';
    final c = formulaCoverage([for (final (_, r) in _recipe) r]);
    if (c.fixedBase <= 0) return null;
    final share = fl.fixedQuantity / c.fixedBase;
    return c.shape == 'mixed'
        ? '${jsNum(roundQty(share * (100 - c.pctTotal)))}% of batch'
        : '${jsNum(roundQty(fl.fixedQuantity))} of ${jsNum(roundQty(c.fixedBase))} parts';
  }

  List<({String name, String unit, num need, num have, num short, num byAdjustment})> get _shortages => [
        for (final l in _lines)
          if (l.ingredientItemId != null && l.d.invQty > 0 && _itemById[l.ingredientItemId] != null)
            if (l.d.invQty - tNum(_itemById[l.ingredientItemId]!['availableFromLots']) > 0.001)
              (
                name: tStr(_itemById[l.ingredientItemId]!['itemName']),
                unit: l.unitOfMeasure.isNotEmpty ? l.unitOfMeasure : tStr(_itemById[l.ingredientItemId]!['unitOfMeasure']),
                need: roundQty(l.d.invQty),
                have: roundQty(tNum(_itemById[l.ingredientItemId]!['availableFromLots'])),
                short: roundQty(l.d.invQty - tNum(_itemById[l.ingredientItemId]!['availableFromLots'])),
                byAdjustment: roundQty(math.max(0, tNum(_itemById[l.ingredientItemId]!['currentQuantity']) - tNum(_itemById[l.ingredientItemId]!['availableFromLots']))),
              ),
      ];

  ({num max, String by})? get _stockLimit {
    final recipe = _recipe;
    if (recipe.isEmpty) return null;
    final factors = formulaUnitFactors([for (final (_, r) in recipe) r]);
    num limit = double.infinity;
    var by = '';
    for (final (k, r) in recipe) {
      final l = _lines.where((x) => x.key == k).firstOrNull;
      if (l == null || l.qtyOverridden || l.sourceType != 'FromInventory') continue;
      final f = factors[r.id];
      final it = l.ingredientItemId != null ? _itemById[l.ingredientItemId] : null;
      if (f == null || f <= 0 || it == null) continue;
      final max = tNum(it['availableFromLots']) / f;
      if (max < limit) {
        limit = max;
        by = tStr(it['itemName']);
      }
    }
    return limit.isFinite ? (max: (limit * 1000).floor() / 1000, by: by) : null;
  }

  List<FeedLine> get _purchasing => [for (final l in _lines) if (l.ingredientItemId != null && l.d.qty > 0 && l.sourceType != 'FromInventory') l];

  String? _validate() {
    if (_finishedId == null) return 'Pick the finished feed this batch produces.';
    if (_qty <= 0) return 'Quantity produced must be greater than zero.';
    final active = [for (final l in _lines) if (l.ingredientItemId != null && l.d.qty > 0) l];
    if (active.isEmpty) return 'Add at least one ingredient line.';
    for (final l in active) {
      if (!l.d.mixedBalanced) return "A mixed-source line's inventory + purchased quantities must equal the quantity used.";
    }
    for (final c in _costs) {
      if (c.d.amount < 0) return 'Additional cost amounts cannot be negative.';
      if (c.paymentStatus == 'Partial' && _n(c.amountPaid) > c.d.amount) return 'Amount paid cannot exceed the cost amount.';
    }
    return null;
  }

  String? _postBlocker() {
    final p = _purchasing;
    if (p.isEmpty) return null;
    final names = [for (final l in p) if (tStr(_itemById[l.ingredientItemId]?['itemName']).isNotEmpty) tStr(_itemById[l.ingredientItemId]?['itemName'])];
    return 'Use Record purchase on the ${names.isNotEmpty ? names.join(', ') : 'ingredient'} line${names.length == 1 ? '' : 's'} — it books the stock and switches the line to From Inventory.';
  }

  Map<String, Object?> _body() {
    final active = [for (final l in _lines) if (l.ingredientItemId != null && l.d.qty > 0) l];
    final costs = [for (final c in _costs) if (c.d.amount > 0) c];
    final d = businessDateAsDateTime(_date);
    return {
      if (widget.existing != null) 'poultryFeedProductionBatchId': tIntOrNull(widget.existing!['poultryFeedProductionBatchId']),
      'batchNumber': _batchNumber.text.isEmpty ? null : _batchNumber.text,
      'productionDate': d == null ? null : DateTime.utc(d.year, d.month, d.day).toIso8601String(),
      'finishedFeedItemId': _finishedId,
      'formulaId': _formulaId,
      'quantityProduced': _qty,
      'outputUnit': _outputUnit.isEmpty ? null : _outputUnit,
      'notes': _notes.text.isEmpty ? null : _notes.text,
      'lines': [
        for (var i = 0; i < active.length; i++)
          () {
            final l = active[i], x = l.d;
            final fixed = _scaling && l.formulaLineId == null && _n(l.enteredQty) > 0;
            return {
              'ingredientItemId': l.ingredientItemId,
              'sourceType': l.sourceType,
              'quantityUsed': x.qty,
              'unitOfMeasure': l.unitOfMeasure.isEmpty ? null : l.unitOfMeasure,
              'quantityMode': fixed ? 'FixedQuantity' : 'Quantity',
              'fixedQuantity': fixed ? _n(l.enteredQty) : null,
              'inventoryQuantityUsed': l.sourceType == 'MixedSource' ? x.invQty : (l.sourceType == 'FromInventory' ? x.qty : 0),
              'purchasedQuantityUsed': l.sourceType == 'MixedSource' ? x.purQty : (l.sourceType == 'BoughtDuringProduction' ? x.qty : 0),
              'inventoryUnitCost': double.parse(x.invUnit.toStringAsFixed(4)),
              'purchasedUnitCost': double.parse(x.purUnit.toStringAsFixed(4)),
              'supplierName': l.supplierName.isEmpty ? null : l.supplierName,
              'purchaseReference': l.purchaseReference.isEmpty ? null : l.purchaseReference,
              'paymentStatus': x.hasPurchase ? l.paymentStatus : null,
              'amountPaid': x.hasPurchase ? x.paid : null,
              'paidFromCashAccountId': x.hasPurchase && x.paid > 0 ? l.paidFromCashAccountId : null,
              'paymentMethod': x.hasPurchase && x.paid > 0 ? l.paymentMethod : null,
              'sortOrder': i,
              'notes': l.notes.isEmpty ? null : l.notes,
            };
          }(),
      ],
      'additionalCosts': [
        for (var i = 0; i < costs.length; i++)
          {
            'costType': costs[i].costType,
            'amount': costs[i].d.amount,
            'paymentStatus': costs[i].paymentStatus,
            'amountPaid': costs[i].d.paid,
            'paidFromCashAccountId': costs[i].d.paid > 0 ? costs[i].paidFromCashAccountId : null,
            'paymentMethod': costs[i].d.paid > 0 ? costs[i].paymentMethod : null,
            'payeeName': costs[i].payeeName.isEmpty ? null : costs[i].payeeName,
            'sortOrder': i,
            'notes': costs[i].notes.isEmpty ? null : costs[i].notes,
          },
      ],
      'farmId': _farmId,
      'userId': _userId,
    };
  }

  Future<Map> _persist() async {
    final r = await _api.post('/api/Poultry/feed-production', body: _body());
    return r is Map ? r : {};
  }

  Future<void> _save() async {
    if (_busy) return;
    final err = _validate();
    if (err != null) {
      trackerToast(context, err, error: true);
      return;
    }
    setState(() {
      _busy = true;
      _saving = true;
    });
    try {
      final saved = await _persist();
      if (!mounted) return;
      final no = tStr(saved['batchNumber']);
      trackerToast(context, widget.existing != null ? 'Draft updated' : 'Draft saved', description: no.isNotEmpty ? 'Batch $no' : null);
      widget.onSaved(tIntOrNull(saved['poultryFeedProductionBatchId']) ?? 0);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to save batch', description: e.message, error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _saving = false;
        });
      }
    }
  }

  void _requestPost() {
    final err = _validate();
    if (err != null) {
      trackerToast(context, err, error: true);
      return;
    }
    final bought = _postBlocker();
    if (bought != null) {
      trackerToast(context, 'Purchase not recorded yet', description: bought, error: true);
      return;
    }
    if (_shortages.isNotEmpty) {
      _shortDialog();
      return;
    }
    _saveAndPost();
  }

  Future<void> _saveAndPost() async {
    if (_busy) return;
    final err = _validate();
    if (err != null) {
      trackerToast(context, err, error: true);
      return;
    }
    setState(() {
      _busy = true;
      _posting = true;
    });
    try {
      final saved = await _persist();
      final id = tIntOrNull(saved['poultryFeedProductionBatchId']) ?? 0;
      final posted = await _api.post('/api/Poultry/feed-production/$id/post', body: {'farmId': _farmId, 'userId': _userId});
      if (!mounted) return;
      trackerToast(context, 'Batch posted', description: 'Cost/unit ${_gh(posted is Map ? tNum(posted['costPerOutputUnit']) : 0)} · stock & cash updated.');
      widget.onSaved(id);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to post batch', description: readableFeedError(e.message), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _posting = false;
        });
      }
    }
  }

  Future<void> _applyFormula(int formulaId) async {
    setState(() => _formulaId = formulaId);
    try {
      final full = await _api.get('/api/Poultry/feed-formulas/$formulaId', query: _farm);
      if (!mounted || full is! Map) return;
      final fls = [for (final x in (full['lines'] as List? ?? const [])) if (x is Map) x];
      final byId = _itemById;
      final seeded = [
        for (final fl in fls)
          FeedLine()
            ..ingredientItemId = tIntOrNull(fl['ingredientItemId'])
            ..formulaLineId = tIntOrNull(fl['poultryFeedFormulaLineId'])
            ..unitOfMeasure = tStr(fl['unitOfMeasure']).isNotEmpty ? tStr(fl['unitOfMeasure']) : tStr(byId[tIntOrNull(fl['ingredientItemId'])]?['unitOfMeasure'])
            ..inventoryUnitCost = byId[tIntOrNull(fl['ingredientItemId'])] != null ? jsNum(tNum(byId[tIntOrNull(fl['ingredientItemId'])]!['latestUnitCost'])) : '',
      ];
      _set(() {
        _formulaId = formulaId;
        _finishedId = tIntOrNull(full['finishedFeedItemId']) ?? _finishedId;
        if (seeded.isNotEmpty) {
          _lines = [...seeded, for (final l in _lines) if (l.formulaLineId == null && l.ingredientItemId != null && _n(l.enteredQty) > 0) l];
        }
        _applied = full;
      });
      trackerToast(context, 'Formula applied', description: '${seeded.length} ingredient${seeded.length == 1 ? '' : 's'} — quantities follow the quantity produced.');
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to apply formula', description: e.message, error: true);
    }
  }

  Future<void> _recordPurchase(FeedLine line) async {
    final buy = line.d.purQty;
    final main = _accounts.where((a) => tStr(a['accountName']).trim().toLowerCase() == 'main cash account').firstOrNull ?? _accounts.firstOrNull;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => RawPurchaseDialog(
        session: widget.session,
        company: widget.company,
        items: _rawItems,
        cashAccounts: _accounts,
        money: _gh,
        defaultItemId: line.ingredientItemId,
        defaultQuantity: buy > 0 ? roundQty(buy) : null,
        defaultCashAccountId: tIntOrNull(main?['poultryCashAccountId']),
      ),
    );
    if (ok != true || !mounted) return;
    _set(() {
      line.sourceType = 'FromInventory';
      line.inventoryQuantityUsed = '';
      line.purchasedQuantityUsed = '';
    });
    try {
      final fresh = rowsOf(await _api.get('/api/Poultry/feed-production/items', query: _farm));
      if (!mounted) return;
      _set(() => _items = fresh);
      final it = fresh.where((i) => tIntOrNull(i['poultryRawMaterialItemId']) == line.ingredientItemId).firstOrNull;
      trackerToast(context, 'Stock updated',
          description: it != null
              ? '${tStr(it['itemName'])} — ${loc(tNum(it['availableFromLots']))} available to draw. The line now draws from inventory.'
              : 'The line now draws from inventory.');
    } on ApiException {
      if (mounted) trackerToast(context, 'Purchase saved', description: 'Reload the page if the available stock looks stale.');
    }
  }

  void _shortDialog() {
    final s = _shortages;
    final limit = _stockLimit;
    const b = TextStyle(fontWeight: FontWeight.w600);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Not enough ingredient stock to post'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('This batch needs more than these ingredients have available to draw:', style: TextStyle(fontSize: 14, color: TColors.slate600)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: TColors.red50, border: Border.all(color: TColors.red200), borderRadius: BorderRadius.circular(6)),
              child: Column(children: [
                for (final x in s)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text(x.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF991B1B)))),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('needs ${loc(x.need)}, only ${loc(x.have)}${x.unit.isNotEmpty ? ' ${x.unit}' : ''} available',
                          textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, color: Color(0xFF991B1B))),
                    ),
                  ]),
              ]),
            ),
            const SizedBox(height: 10),
            const Text('What you can do:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
            Text('•  Lower the quantity produced${limit != null && limit.max > 0 ? ' — stock covers about ${loc(limit.max)}' : ''}.',
                style: const TextStyle(fontSize: 14, color: TColors.slate600)),
            const Text.rich(TextSpan(children: [
              TextSpan(text: '•  Buy the shortfall: set the line to '),
              TextSpan(text: 'Bought During Production', style: b),
              TextSpan(text: ' or '),
              TextSpan(text: 'Mixed Source', style: b),
              TextSpan(text: ' and use '),
              TextSpan(text: 'Record purchase', style: b),
              TextSpan(text: ' — the new stock is drawable straight away.'),
            ]), style: TextStyle(fontSize: 14, color: TColors.slate600)),
            if (s.any((x) => x.byAdjustment > 0))
              const Text.rich(TextSpan(children: [
                TextSpan(text: '•  Record a '),
                TextSpan(text: 'purchase', style: b),
                TextSpan(text: ' for stock that was added by adjustment — adjusted stock has no batch to draw from.'),
              ]), style: TextStyle(fontSize: 14, color: TColors.slate600)),
          ]),
        ),
        actions: [OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  // ------------------------------------------------------------ build

  Widget _field(String label, Widget child, {String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
          const SizedBox(height: 6),
          child,
          if (hint != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(hint, style: const TextStyle(fontSize: 12, color: TColors.slate500))),
        ]),
      );

  Widget _small(String t) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(t, style: const TextStyle(fontSize: 12, color: TColors.slate500)));

  Widget _row(String l, String v, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(l, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w600 : null, color: bold ? TColors.slate900 : TColors.slate600))),
          Text(v, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w600 : null, color: color ?? (bold ? TColors.slate900 : null))),
        ]),
      );

  Widget _card(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: .6, color: TColors.slate500)),
            const SizedBox(height: 6),
            ...children,
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Row(children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 8), Text('Loading…')]),
      );
    }
    final unit = _outputUnit;
    final qty = _qty;
    final recipe = _recipe;
    final totalIngredient = _lines.fold<num>(0, (s, l) => s + l.d.total);
    final totalAdditional = _costs.fold<num>(0, (s, c) => s + c.d.amount);
    final totalCost = totalIngredient + totalAdditional;
    final totalIngredientQty = _lines.fold<num>(0, (s, l) => s + (l.ingredientItemId != null ? l.d.qty : 0));
    final hasOverrides = _lines.any((l) => l.qtyOverridden);
    final costPerUnit = qty > 0 ? totalCost / qty : 0;
    final covers = qty <= 0 || (totalIngredientQty - qty).abs() <= qty * 0.005;
    final shortages = _shortages;
    final limit = _stockLimit;
    final coverage = formulaCoverage([for (final (_, r) in recipe) r]);
    final cashOut = <int, num>{};
    void add(int? id, num amt) {
      if (id == null || id == 0 || amt <= 0) return;
      cashOut[id] = (cashOut[id] ?? 0) + amt;
    }

    for (final l in _lines) {
      add(l.paidFromCashAccountId, l.d.paid);
    }
    for (final c in _costs) {
      add(c.paidFromCashAccountId, c.d.paid);
    }
    final totalCashOut = cashOut.values.fold<num>(0, (s, v) => s + v);
    final totalPayable = _lines.fold<num>(0, (s, l) => s + l.d.payable) + _costs.fold<num>(0, (s, c) => s + c.d.payable);
    final finishedName = _finishedItems.where((i) => tIntOrNull(i['poultryRawMaterialItemId']) == _finishedId).firstOrNull?['itemName'];
    final purchasing = _purchasing;
    String acctName(int id) {
      final a = _accounts.where((a) => tIntOrNull(a['poultryCashAccountId']) == id).firstOrNull;
      return a != null ? tStr(a['accountName']) : 'Account #$id';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        TextButton.icon(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, size: 16), label: const Text('Back')),
        Text(widget.existing != null ? 'Edit Batch ${tStr(widget.existing!['batchNumber'])}' : 'New Feed Production Batch',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        if (widget.existing != null) const TBadge('Draft', bg: Colors.white, fg: TColors.slate700, border: TColors.slate200),
      ]),
      const SizedBox(height: 12),
      formSection('Finished feed output', TColors.blue600, [
        _field(
          'Finished feed *',
          AppSelect<String>(
            value: _finishedId == null ? null : '$_finishedId',
            hintText: _finishedItems.isNotEmpty ? 'Pick finished feed' : 'No finished-feed items — create one first',
            items: [for (final i in _finishedItems) AppSelectItem(value: tStr(i['poultryRawMaterialItemId']), label: tStr(i['itemName']))],
            onChanged: (v) => _set(() => _finishedId = int.tryParse(v ?? '')),
          ),
        ),
        _field(
          'Feed formula',
          AppSelect<String>(
            value: _formulaId == null ? null : '$_formulaId',
            hintText: _activeFormulas.isNotEmpty ? 'Pick a formula' : 'No formulas',
            items: [for (final f in _activeFormulas) AppSelectItem(value: tStr(f['poultryFeedFormulaId']), label: tStr(f['formulaName']))],
            onChanged: (v) {
              final id = int.tryParse(v ?? '');
              if (id != null) _applyFormula(id);
            },
          ),
          hint: 'Optional — without one, the quantities you type below are scaled to fill the batch',
        ),
        _field('Production date', AppDateField(value: businessDateAsDateTime(_date), onChanged: (v) => setState(() => _date = v == null ? '' : isoDay(v)))),
        _field(
          'Quantity produced *',
          _Box(key: const ValueKey('fp-qty'), value: _qtyProduced, onChanged: (v) => _set(() => _qtyProduced = v)),
          hint: _applied != null
              ? 'Ingredients redistribute from ${tStr(_applied!['formulaName'])} as you type'
              : recipe.isNotEmpty
                  ? 'Ingredients rescale to fill the batch as you type'
                  : null,
        ),
        _field('Output unit', AppInput(key: ValueKey('fp-unit-$unit'), initialValue: unit, hintText: '—', enabled: false), hint: _unitSource),
        _field('Batch number', AppInput(controller: _batchNumber, hintText: 'FP-2026-0001'), hint: 'Auto-generated if left blank'),
        _field('Notes', AppInput(controller: _notes, minLines: 2, maxLines: 4)),
      ]),
      const SizedBox(height: 14),
      formSection('Ingredient breakdown', TColors.emerald600, [
        if (_scaling)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
            child: Text.rich(TextSpan(children: [
              const TextSpan(text: 'No formula picked — the quantities you type are read as a '),
              const TextSpan(text: 'recipe', style: TextStyle(fontWeight: FontWeight.w500)),
              TextSpan(
                  text: ' and scaled to fill the batch. For a ${qty > 0 ? loc(qty) : '500'}${unit.isNotEmpty ? ' $unit' : ''} batch, typing 50 / 30 / 20 uses '
                      '${qty > 0 ? '${loc(roundQty(qty * .5))} / ${loc(roundQty(qty * .3))} / ${loc(roundQty(qty * .2))}' : '250 / 150 / 100'}. '
                      'Quantities that already add up to the batch are used as they are.'),
            ]), style: const TextStyle(fontSize: 12, color: TColors.slate600)),
          ),
        for (final l in _lines) _lineCard(l, recipe),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: () => _set(() => _lines.add(FeedLine())), icon: const Icon(Icons.add, size: 16), label: const Text('Add ingredient')),
          if (_applied != null)
            TextButton.icon(
              onPressed: hasOverrides
                  ? () {
                      _set(() {
                        for (final l in _lines) {
                          l.qtyOverridden = false;
                        }
                      });
                      trackerToast(context, 'Reset to formula', description: 'Edited quantities now follow the quantity produced again.');
                    }
                  : null,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text('Reset to ${tStr(_applied!['formulaName'])}'),
            ),
        ]),
        if (shortages.isNotEmpty) _shortageBox(shortages),
        if (limit != null && limit.by.isNotEmpty && qty > limit.max)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: TColors.amber300), borderRadius: BorderRadius.circular(6)),
            child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Stock covers about '),
                TextSpan(text: loc(limit.max), style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: '${unit.isNotEmpty ? ' $unit' : ''} ${_applied != null ? 'with this formula' : 'at these proportions'} — limited by '),
                TextSpan(text: limit.by, style: const TextStyle(fontWeight: FontWeight.w500)),
                const TextSpan(text: '.'),
              ]), style: const TextStyle(fontSize: 12, color: Color(0xFF92400E))),
              if (limit.max > 0)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => _set(() => _qtyProduced = jsNum(limit.max)),
                  child: Text('Use ${loc(limit.max)}', style: const TextStyle(fontSize: 12)),
                ),
            ]),
          ),
        if (_applied != null && qty > 0)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: covers ? TColors.slate50 : TColors.amber50,
              border: Border.all(color: covers ? TColors.slate200 : TColors.amber300),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text.rich(TextSpan(children: [
              const TextSpan(text: 'Ingredients total '),
              TextSpan(text: loc(roundQty(totalIngredientQty)), style: const TextStyle(fontWeight: FontWeight.w600)),
              const TextSpan(text: ' of '),
              TextSpan(text: loc(qty), style: const TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: '${unit.isNotEmpty ? ' $unit' : ''} produced (${(totalIngredientQty / qty * 100).toStringAsFixed(1)}%)'),
              if (!covers) ...[
                const TextSpan(text: ' — check '),
                TextSpan(text: tStr(_applied!['formulaName']), style: const TextStyle(fontWeight: FontWeight.w500)),
                TextSpan(
                    text: coverage.shape != 'fixed' && (coverage.pctTotal - 100).abs() > 0.01
                        ? ': its percentages total ${jsNum(roundQty(coverage.pctTotal))}%, not 100%.'
                        : '.'),
              ],
            ]), style: TextStyle(fontSize: 12, color: covers ? TColors.slate600 : const Color(0xFF92400E))),
          ),
      ]),
      const SizedBox(height: 14),
      formSection('Additional production costs', TColors.amber600, [
        if (_costs.isEmpty) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('No additional costs. Add grinding, labor, transport, etc. if any.', style: TextStyle(fontSize: 14, color: TColors.slate400))),
        for (final c in _costs) _costCard(c),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(onPressed: () => _set(() => _costs.add(FeedCost())), icon: const Icon(Icons.add, size: 16), label: const Text('Add cost')),
        ),
      ]),
      const SizedBox(height: 14),
      _card('Cost summary', [
        _row('Total ingredient cost', _gh(totalIngredient)),
        _row('Additional production costs', _gh(totalAdditional)),
        const Divider(height: 10),
        _row('Total production cost', _gh(totalCost), bold: true),
        _row('Cost per unit${unit.isNotEmpty ? ' ($unit)' : ''}', _gh(costPerUnit), bold: true),
        _row('Quantity produced', '${loc(qty)}${unit.isNotEmpty ? ' $unit' : ''}'),
      ]),
      _card('Inventory impact', [
        for (final l in _lines)
          if (l.ingredientItemId != null && l.d.invQty > 0) _row(tStr(_itemById[l.ingredientItemId]?['itemName']), '-${loc(l.d.invQty)}', color: TColors.red600),
        if (purchasing.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFEEF2FF), border: Border.all(color: const Color(0xFFC7D2FE)), borderRadius: BorderRadius.circular(4)),
            child: Text('${purchasing.length} ingredient${purchasing.length == 1 ? '' : 's'} awaiting a purchase — not counted here.',
                style: const TextStyle(fontSize: 11, color: Color(0xFF4338CA))),
          ),
        const Divider(height: 10),
        Row(children: [
          Expanded(child: Text(tStr(finishedName).isNotEmpty ? tStr(finishedName) : 'Finished feed', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
          Text('+${loc(qty)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.emerald600)),
        ]),
      ]),
      _card('Cash & payable impact', [
        for (final e in cashOut.entries) _row(acctName(e.key), '-${_gh(e.value)}', color: TColors.red600),
        Row(children: [
          const Expanded(child: Text('Total cash out', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
          Text(_gh(totalCashOut), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ]),
        const Divider(height: 10),
        _row('Supplier payables (unpaid)', _gh(totalPayable), color: totalPayable > 0 ? TColors.red600 : TColors.emerald600),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text("Cash & payables post when the batch is posted, not while it's a draft.", style: TextStyle(fontSize: 11, color: TColors.slate400)),
        ),
      ]),
      Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
        OutlinedButton(onPressed: _saving || _posting ? null : () => Navigator.of(context).maybePop(), child: const Text('Cancel')),
        OutlinedButton.icon(
          onPressed: _saving || _posting ? null : _save,
          icon: const Icon(Icons.save_outlined, size: 16),
          label: Text(_saving ? 'Saving…' : 'Save Draft'),
        ),
        if (_canPost)
          FilledButton.icon(
            onPressed: _saving || _posting ? null : _requestPost,
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: Text(_posting ? 'Posting…' : 'Save & Post'),
          ),
      ]),
      const SizedBox(height: 24),
    ]);
  }

  Widget _shortageBox(List<({String name, String unit, num need, num have, num short, num byAdjustment})> s) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: TColors.red50, border: Border.all(color: TColors.red300), borderRadius: BorderRadius.circular(6)),
        child: DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Not enough stock for ${s.length} ingredient${s.length == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w600)),
            for (final x in s)
              Text.rich(TextSpan(children: [
                TextSpan(text: '${x.name} — need ${loc(x.need)}, available ${loc(x.have)}'),
                TextSpan(text: ' (short ${loc(x.short)}${x.unit.isNotEmpty ? ' ${x.unit}' : ''})', style: const TextStyle(fontWeight: FontWeight.w600)),
              ])),
            const Text.rich(TextSpan(children: [
              TextSpan(text: 'Reduce the quantity produced, or set the short lines to '),
              TextSpan(text: 'Bought During Production', style: TextStyle(fontWeight: FontWeight.w500)),
              TextSpan(text: ' / '),
              TextSpan(text: 'Mixed Source', style: TextStyle(fontWeight: FontWeight.w500)),
              TextSpan(text: " and record the purchase from the line. This batch can't be posted until it fits."),
            ]), style: TextStyle(color: TColors.red700)),
            if (s.any((x) => x.byAdjustment > 0))
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Some of this stock was added by a '),
                const TextSpan(text: 'stock adjustment', style: TextStyle(fontWeight: FontWeight.w500)),
                TextSpan(
                    text: ' rather than a purchase, so there is no batch to draw it from'
                        '${[for (final x in s) if (x.byAdjustment > 0) ' (${x.name}: ${loc(x.byAdjustment)})'].join(', ')}. Record it as a purchase to make it usable.'),
              ]), style: const TextStyle(color: TColors.red700)),
          ]),
        ),
      );

  Widget _lineCard(FeedLine l, List<(String, RecipeLine)> recipe) {
    final d = l.d;
    final it = l.ingredientItemId != null ? _itemById[l.ingredientItemId] : null;
    final avail = tNum(it?['availableFromLots']);
    final shortBy = it != null && d.invQty > avail ? roundQty(d.invQty - avail) : 0;
    final fromFormula = l.formulaLineId != null;
    final inRecipe = recipe.any((e) => e.$1 == l.key);
    final scaledTo = !fromFormula && inRecipe && (d.qty - _n(l.enteredQty)).abs() > 0.001 ? d.qty : null;
    final isBought = l.sourceType == 'BoughtDuringProduction';
    final u = l.unitOfMeasure.isNotEmpty ? ' ${l.unitOfMeasure}' : '';
    return Container(
      key: ValueKey('fp-line-${l.key}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: shortBy > 0 ? TColors.red300 : TColors.slate200), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (it != null || scaledTo != null || isBought)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(spacing: 12, runSpacing: 2, children: [
              if (it != null && !isBought)
                shortBy > 0
                    ? Text('Short ${loc(shortBy)} — only ${loc(avail)} of ${tStr(it['itemName'])} available to draw',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: TColors.red600))
                    : Text('Available: ${loc(avail)}$u', style: const TextStyle(fontSize: 11, color: TColors.slate400)),
              if (scaledTo != null) Text('→ uses ${loc(scaledTo)}$u', style: const TextStyle(fontSize: 11, color: TColors.emerald600)),
              if (isBought) const Text('Cost comes from the purchase you record', style: TextStyle(fontSize: 11, color: TColors.slate400)),
            ]),
          ),
        _small('Ingredient'),
        AppSelect<String>(
          value: l.ingredientItemId == null ? null : '${l.ingredientItemId}',
          hintText: 'Pick ingredient',
          items: [for (final i in _ingredientItems) AppSelectItem(value: tStr(i['poultryRawMaterialItemId']), label: tStr(i['itemName']))],
          onChanged: (v) {
            final id = int.tryParse(v ?? '');
            final item = id != null ? _itemById[id] : null;
            _set(() {
              l.ingredientItemId = id;
              l.unitOfMeasure = tStr(item?['unitOfMeasure']);
              l.inventoryUnitCost = item != null ? jsNum(tNum(item['latestUnitCost'])) : '';
            });
          },
        ),
        const SizedBox(height: 8),
        _small('Source'),
        AppSelect<String>(
          value: l.sourceType,
          items: [for (final (v, t) in feedSourceTypes) AppSelectItem(value: v, label: t)],
          onChanged: (v) => _set(() => l.sourceType = v ?? l.sourceType),
        ),
        const SizedBox(height: 8),
        _small('Qty used${l.unitOfMeasure.isNotEmpty ? ' (${l.unitOfMeasure})' : ''}'),
        _Box(
          key: ValueKey('fp-q-${l.key}'),
          value: fromFormula ? l.quantityUsed : l.enteredQty,
          onChanged: (v) => _set(() {
            if (fromFormula) {
              l.quantityUsed = v;
              l.qtyOverridden = true;
            } else {
              l.enteredQty = v;
            }
          }),
        ),
        if (l.qtyOverridden)
          Row(children: [
            const Text('✎ edited — ', style: TextStyle(fontSize: 11, color: TColors.amber600)),
            InkWell(
              onTap: () => _set(() => l.qtyOverridden = false),
              child: const Text('reset', style: TextStyle(fontSize: 11, color: TColors.amber600, decoration: TextDecoration.underline)),
            ),
          ])
        else if (fromFormula)
          Text(_shareOf(l) ?? 'Follows the quantity produced', style: const TextStyle(fontSize: 11, color: TColors.slate400)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: isBought
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _small('Cost'),
                    const Text('—', style: TextStyle(fontWeight: FontWeight.w500, color: TColors.slate400)),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _small('Cost from stock'),
                    Text(_gh(d.invCost), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate800)),
                    Text(
                      d.hasPurchase ? '${_gh(d.invUnit)}/unit — the bought part is priced by its purchase' : '${_gh(d.unit)}/unit — priced from stock lots at posting',
                      style: const TextStyle(fontSize: 11, color: TColors.slate400),
                    ),
                  ]),
          ),
          IconButton(
            tooltip: 'Remove ingredient',
            onPressed: _lines.length <= 1 ? null : () => _set(() => _lines.remove(l)),
            icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600),
          ),
        ]),
        if (l.sourceType == 'MixedSource') ...[
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _small('From inventory qty'),
                _Box(key: ValueKey('fp-inv-${l.key}'), value: l.inventoryQuantityUsed, onChanged: (v) => _set(() => l.inventoryQuantityUsed = v)),
                Text('${_gh(d.invCost)} at ${_gh(d.invUnit)}/unit', style: const TextStyle(fontSize: 11, color: TColors.slate400)),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _small('Purchased qty'),
                _Box(key: ValueKey('fp-pur-${l.key}'), value: l.purchasedQuantityUsed, onChanged: (v) => _set(() => l.purchasedQuantityUsed = v)),
                const Text('The part to buy in Raw Materials', style: TextStyle(fontSize: 11, color: TColors.slate400)),
              ]),
            ),
          ]),
          if (!d.mixedBalanced)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Inventory + purchased must equal ${d.qty != 0 ? jsNum(d.qty) : 'qty used'}', style: const TextStyle(fontSize: 11, color: TColors.amber600)),
            ),
        ],
        if (d.hasPurchase)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFEEF2FF), border: Border.all(color: const Color(0xFFC7D2FE)), borderRadius: BorderRadius.circular(6)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Row(children: [
                Icon(Icons.shopping_cart_outlined, size: 14, color: Color(0xFF312E81)),
                SizedBox(width: 6),
                Flexible(child: Text('Purchases are recorded in Raw Materials', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF312E81)))),
              ]),
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(children: [
                  if (isBought) ...[
                    const TextSpan(text: 'Record it'),
                    if (it != null) ...[const TextSpan(text: ' for '), TextSpan(text: tStr(it['itemName']), style: const TextStyle(fontWeight: FontWeight.w500))],
                    const TextSpan(text: ' here without leaving the batch — it creates the stock lot and switches this line to '),
                    const TextSpan(text: 'From Inventory', style: TextStyle(fontWeight: FontWeight.w500)),
                    const TextSpan(text: '.'),
                  ] else ...[
                    const TextSpan(text: 'Buy the '),
                    d.purQty > 0 ? TextSpan(text: '${loc(d.purQty)}$u', style: const TextStyle(fontWeight: FontWeight.w500)) : const TextSpan(text: 'part'),
                    const TextSpan(text: " stock can't cover"),
                    if (it != null) ...[const TextSpan(text: ' of '), TextSpan(text: tStr(it['itemName']), style: const TextStyle(fontWeight: FontWeight.w500))],
                    TextSpan(text: ' here; the line then draws the full ${d.qty > 0 ? loc(d.qty) : 'quantity'} from inventory.'),
                  ],
                  const TextSpan(text: " This batch can't be posted until you do."),
                ]),
                style: const TextStyle(fontSize: 12, color: Color(0xFF3730A3)),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white, foregroundColor: const Color(0xFF3730A3), side: const BorderSide(color: Color(0xFFA5B4FC))),
                  onPressed: () => _recordPurchase(l),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Record purchase'),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _costCard(FeedCost c) => Container(
        key: ValueKey('fp-cost-${c.key}'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _small('Type'),
                AppSelect<String>(
                  value: c.costType,
                  items: [for (final t in feedCostTypes) AppSelectItem(value: t, label: feedCostLabel(t))],
                  onChanged: (v) => _set(() => c.costType = v ?? c.costType),
                ),
              ]),
            ),
            IconButton(tooltip: 'Remove cost', onPressed: () => _set(() => _costs.remove(c)), icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600)),
          ]),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _small('Amount'),
                _Box(key: ValueKey('fp-amt-${c.key}'), value: c.amount, onChanged: (v) => _set(() => c.amount = v)),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _small('Payment'),
                AppSelect<String>(
                  value: c.paymentStatus,
                  items: [for (final s in feedPaymentStatuses) AppSelectItem(value: s, label: s)],
                  onChanged: (v) => _set(() => c.paymentStatus = v ?? c.paymentStatus),
                ),
              ]),
            ),
          ]),
          if (c.paymentStatus == 'Partial') ...[
            const SizedBox(height: 8),
            _small('Amount paid'),
            _Box(key: ValueKey('fp-paid-${c.key}'), value: c.amountPaid, onChanged: (v) => _set(() => c.amountPaid = v)),
          ],
          if (c.paymentStatus != 'Unpaid') ...[
            const SizedBox(height: 8),
            _small('Paid from'),
            AppSelect<String>(
              value: c.paidFromCashAccountId == null ? null : '${c.paidFromCashAccountId}',
              hintText: 'Account',
              items: [for (final a in _accounts) AppSelectItem(value: tStr(a['poultryCashAccountId']), label: tStr(a['accountName']))],
              onChanged: (v) => _set(() => c.paidFromCashAccountId = int.tryParse(v ?? '')),
            ),
          ],
          const SizedBox(height: 8),
          _small('Payee / notes'),
          AppInput(key: ValueKey('fp-payee-${c.key}'), initialValue: c.payeeName, hintText: 'Who was paid', onChanged: (v) => _set(() => c.payeeName = v)),
        ]),
      );
}
