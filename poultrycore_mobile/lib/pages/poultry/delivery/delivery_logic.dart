// The Deliveries page's rules (app/poultry-driver-returns/page.tsx), kept free
// of widgets: the list filters, the return's crate and cash arithmetic, the
// checks before saving, and the body the API receives.

import 'package:flutter/material.dart';

import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart' show TColors;

const deliveryExpenseCategories = ['Fuel', 'ChopMoney', 'LoadingBoys', 'Toll', 'Repair', 'PhoneCredit', 'Other'];

/// prettyCategory: "ChopMoney" → "Chop Money".
String prettyCategory(String c) => c.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');

/// LOAD_STATUS (and the detail page's extra Draft / Approved tones).
(Color, Color) loadStatusTone(Object? s) => switch (tStr(s)) {
      'Loaded' => (TColors.blue100, const Color(0xFF1D4ED8)),
      'Returned' => (TColors.amber100, TColors.amber700),
      'Reconciled' || 'Approved' => (TColors.green100, TColors.green700),
      'Draft' => (TColors.slate100, TColors.slate600),
      'Cancelled' => (TColors.slate100, TColors.slate700),
      _ => (Colors.transparent, TColors.slate700),
    };

/// The returns table's status badge.
(Color, Color) returnStatusTone(Object? s) => switch (tStr(s)) {
      'Approved' => (TColors.green100, TColors.green700),
      'Cancelled' => (TColors.slate100, TColors.slate600),
      _ => (TColors.amber100, TColors.amber700),
    };

String? _day(Object? raw) => RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(tStr(raw))?[1];

class DeliveryFilters {
  String driver = 'ALL', vehicle = 'ALL', route = 'ALL', status = 'ALL';
}

bool _dropdowns(DeliveryFilters f, {Object? driverId, Object? vehicleId, Object? routeId, Object? status}) {
  if (f.driver != 'ALL' && tStr(driverId) != f.driver) return false;
  if (f.vehicle != 'ALL' && tStr(vehicleId) != f.vehicle) return false;
  if (f.route != 'ALL' && tStr(routeId) != f.route) return false;
  if (f.status != 'ALL' && tStr(status) != f.status) return false;
  return true;
}

bool _dateAndSearch(Map r, String dateKey, String search, String from, String to) {
  final day = _day(r[dateKey]);
  if (day != null) {
    if (from.isNotEmpty && day.compareTo(from) < 0) return false;
    if (to.isNotEmpty && day.compareTo(to) > 0) return false;
  }
  final s = search.trim().toLowerCase();
  if (s.isNotEmpty && !['driverName', 'vehicleName', 'routeName'].any((k) => r[k] != null && '${r[k]}'.toLowerCase().contains(s))) {
    return false;
  }
  return true;
}

List<Map> visibleLoadings(List<Map> loadings, DeliveryFilters f, {String search = '', String from = '', String to = ''}) => [
      for (final l in loadings)
        if (_dateAndSearch(l, 'loadDate', search, from, to) &&
            _dropdowns(f, driverId: l['poultryDriverId'], vehicleId: l['poultryVehicleId'], routeId: l['poultryRouteId'], status: l['status']))
          l,
    ];

/// Returns are matched on their loading's driver / vehicle / route.
List<Map> visibleReturns(List<Map> returns, List<Map> loadings, DeliveryFilters f, {String search = '', String from = '', String to = ''}) => [
      for (final r in returns)
        if (_dateAndSearch(r, 'returnDate', search, from, to))
          if (_parentMatches(r, loadings, f)) r,
    ];

bool _parentMatches(Map r, List<Map> loadings, DeliveryFilters f) {
  final p = loadings.where((l) => tStr(l['poultryVehicleLoadingId']) == tStr(r['poultryVehicleLoadingId'])).firstOrNull;
  return _dropdowns(f, driverId: p?['poultryDriverId'], vehicleId: p?['poultryVehicleId'], routeId: p?['poultryRouteId'], status: r['status']);
}

/// Products a delivery can carry: active eggs, birds and finished goods.
List<Map> deliverableProducts(List<Map> products) => [
      for (final p in products)
        if (p['isActive'] == true &&
            (p['isRawEggProduct'] == true || p['isBirdProduct'] == true || (tStr(p['productType']).isEmpty ? 'FinishedGood' : tStr(p['productType'])) == 'FinishedGood'))
          p,
    ];

// ------------------------------------------------------------ the load form

class LoadItem {
  LoadItem(this.productId, {this.crates = 0, this.unitPrice = 0, this.eggsPerCrate = 30, this.notes = ''});
  int productId;
  num crates, unitPrice, eggsPerCrate;
  String notes;
}

/// saveLoad's checks, in order: (title, description) of the first failure.
(String, String?)? loadProblem({required int vehicleId, required int driverId, required List<LoadItem> items}) {
  if (vehicleId == 0) return ('Pick a vehicle', null);
  if (driverId == 0) return ('Driver is required', 'Drivers carry the stock and the money — the system needs to know who.');
  if (items.isEmpty) return ('Add at least one product line', null);
  if (items.any((i) => i.productId == 0 || i.crates <= 0)) return ('Each line needs a product and a quantity > 0', null);
  final seen = <int>{};
  for (final i in items) {
    if (!seen.add(i.productId)) return ('Duplicate product line', 'Each product can only appear once per load.');
  }
  return null;
}

// ------------------------------------------------------------ the return form

class ReturnItem {
  ReturnItem({
    required this.productId,
    required this.productName,
    required this.loaded,
    this.sold = 0,
    this.returned = 0,
    this.damaged = 0,
    this.unitPrice = 0,
  });
  int productId;
  String productName;
  num loaded, sold, returned, damaged, unitPrice;
  num get accounted => sold + returned + damaged;
  bool get balanced => accounted == loaded;
}

class BreakdownItem {
  BreakdownItem(this.productId, {this.quantity = 1, this.unitPrice = 0});
  int productId;
  num quantity, unitPrice;
}

class BreakdownRow {
  BreakdownRow({this.customerId, this.label = '', this.cash = 0, this.momo = 0, this.bank = 0, this.credit = 0, this.notes = '', List<BreakdownItem>? items})
      : items = items ?? [];
  int? customerId;
  String label, notes;
  num cash, momo, bank, credit;
  List<BreakdownItem> items;
  num get lineTotal => items.fold<num>(0, (s, i) => s + i.quantity * i.unitPrice);
  num get paidPlusCredit => cash + momo + bank + credit;
  bool get mismatch => (lineTotal - paidPlusCredit).abs() > 0.01;
}

class ExpenseRow {
  ExpenseRow({this.category = 'Fuel', this.amount = 0, this.description = '', this.approved = true});
  String category, description;
  num amount;
  bool approved;
}

class ReturnPayments {
  num cash = 0, momo = 0, bank = 0, credit = 0, floatBack = 0;
}

/// Every figure the return dialog shows and checks.
class ReturnCalc {
  ReturnCalc({
    required this.items,
    required this.pay,
    required this.breakdown,
    required this.expenses,
    required this.detailed,
    required this.loading,
  });
  final List<ReturnItem> items;
  final ReturnPayments pay;
  final List<BreakdownRow> breakdown;
  final List<ExpenseRow> expenses;
  final bool detailed;
  final Map loading;

  num get sold => items.fold<num>(0, (s, i) => s + i.sold);
  num get returned => items.fold<num>(0, (s, i) => s + i.returned);
  num get damaged => items.fold<num>(0, (s, i) => s + i.damaged);
  num get accounted => sold + returned + damaged;
  num get loaded => loading['cratesLoaded'] != null ? tNum(loading['cratesLoaded']) : items.fold<num>(0, (s, i) => s + i.loaded);
  bool get perItemBalanced => items.every((i) => i.balanced);
  bool get overallBalanced => accounted == loaded;
  bool get cratesOk => perItemBalanced && overallBalanced;

  num get expectedCash {
    final fromItems = items.fold<num>(0, (s, i) => s + i.sold * i.unitPrice);
    return fromItems != 0 ? fromItems : sold * tNum(loading['expectedSellingPricePerCrate']);
  }

  num get collected => pay.cash + pay.momo + pay.bank + pay.credit;
  num get shortage => (expectedCash - collected) > 0 ? expectedCash - collected : 0;
  num get overage => (collected - expectedCash) > 0 ? collected - expectedCash : 0;

  num _sum(num Function(BreakdownRow) f) => breakdown.fold<num>(0, (s, r) => s + f(r));
  num get bCash => _sum((r) => r.cash);
  num get bMomo => _sum((r) => r.momo);
  num get bBank => _sum((r) => r.bank);
  num get bCredit => _sum((r) => r.credit);
  bool get breakdownProvided => breakdown.isNotEmpty;
  bool get paymentsBalance => bCash == pay.cash && bMomo == pay.momo && bBank == pay.bank && bCredit == pay.credit;
  bool get qtyBalance {
    final qty = <int, num>{};
    for (final r in breakdown) {
      for (final i in r.items) {
        qty[i.productId] = (qty[i.productId] ?? 0) + i.quantity;
      }
    }
    return items.every((ri) => (qty[ri.productId] ?? 0) == ri.sold);
  }

  bool get breakdownBalanced => paymentsBalance && qtyBalance;
  bool get creditWithoutCustomer => detailed && pay.credit > 0 && !breakdownProvided;
  bool get detailedCreditUnassigned => detailed && breakdownProvided && breakdown.any((r) => r.credit > 0 && r.label.trim().isEmpty);

  num get expensesTotal => expenses.fold<num>(0, (s, e) => s + (e.approved ? e.amount : 0));
  num get openingFloat => tNum(loading['openingCashWithDriver']);
  num get expectedFloatBack => (openingFloat - expensesTotal) > 0 ? openingFloat - expensesTotal : 0;
  bool get floatBalanced => (pay.floatBack - expectedFloatBack).abs() < 0.01;

  /// saveReturn's checks, in order, as (title, description).
  (String, String)? problem({required bool override}) {
    if (!perItemBalanced) {
      return ('Per-product crates don\'t reconcile', "Each product line's Sold + Returned + Damaged must equal Loaded.");
    }
    if (!overallBalanced) {
      return ('Totals don\'t reconcile', 'Sold(${_n(sold)}) + Returned(${_n(returned)}) + Damaged(${_n(damaged)}) != Loaded(${_n(loaded)})');
    }
    if (detailed && breakdownProvided && !breakdownBalanced && !override) {
      return ('Customer breakdown doesn\'t match summary', 'Match the totals, click "Use Summary Only", or tick the override.');
    }
    if (detailedCreditUnassigned && !override) {
      return ('Credit not assigned to customers', 'Give each credit row a customer label, or tick the admin override.');
    }
    return null;
  }

  /// PoultryDriverReturnInput (farmId and createdBy are added by the caller).
  Map<String, Object?> body({required int loadingId, required String returnDate, required String notes}) => {
        'poultryVehicleLoadingId': loadingId,
        'returnDate': returnDate,
        'cratesSold': sold,
        'cratesReturned': returned,
        'cratesDamaged': damaged,
        'missingCrates': 0,
        'cashCollected': pay.cash,
        'moMoCollected': pay.momo,
        'bankCollected': pay.bank,
        'creditSalesAmount': pay.credit,
        'cashReturnedByDriver': pay.floatBack,
        'approvedDeliveryExpenses': expensesTotal,
        'salesPostingMode': detailed ? 'Detailed' : 'Summary',
        'primaryCustomerId': null,
        'notes': notes.isEmpty ? null : notes,
        'items': [
          for (final i in items)
            {'poultryProductId': i.productId, 'cratesSold': i.sold, 'cratesReturned': i.returned, 'cratesDamaged': i.damaged, 'unitPrice': i.unitPrice},
        ],
        if (detailed && breakdownProvided)
          'customerSales': [
            for (final r in breakdown)
              {
                'customerId': r.customerId,
                'customerLabel': r.label.isEmpty ? null : r.label,
                'cashPaid': r.cash,
                'moMoPaid': r.momo,
                'bankPaid': r.bank,
                'creditAmount': r.credit,
                'notes': r.notes.isEmpty ? null : r.notes,
                'items': [for (final i in r.items) {'poultryProductId': i.productId, 'quantity': i.quantity, 'unitPrice': i.unitPrice}],
              },
          ],
        if (expenses.isNotEmpty)
          'expenses': [
            for (final e in expenses)
              {'expenseCategory': e.category, 'amount': e.amount, 'description': e.description.isEmpty ? null : e.description, 'isApproved': e.approved},
          ],
      };

  static String _n(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

/// The detail page picks the non-cancelled return first, then the latest.
Map? pickRunReturn(List<Map> returns, int loadingId) {
  final mine = [for (final r in returns) if (tIntOrNull(r['poultryVehicleLoadingId']) == loadingId) r];
  if (mine.isEmpty) return null;
  mine.sort((a, b) {
    final ac = tStr(a['status']) == 'Cancelled' ? 1 : 0, bc = tStr(b['status']) == 'Cancelled' ? 1 : 0;
    if (ac != bc) return ac - bc;
    return (tIntOrNull(b['poultryDriverReturnId']) ?? 0) - (tIntOrNull(a['poultryDriverReturnId']) ?? 0);
  });
  return mine.first;
}
