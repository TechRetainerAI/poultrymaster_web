// Capital Investments/Assets: the wording and arithmetic from
// `lib/poultry/financial-classification.ts` and
// `lib/capital-assets/correction-preview.ts`, kept as plain functions so they
// can be tested without a screen.

import 'package:flutter/material.dart';

import '../trackers/tracker_logic.dart' show tStr;
import '../trackers/tracker_widgets.dart';

const assetStatuses = ['Draft', 'Active', 'FullyDepreciated', 'Disposed', 'Reversed'];

String assetStatusLabel(Object? s) => switch (tStr(s)) {
      'Draft' => 'Not in service',
      'Active' => 'In service',
      'FullyDepreciated' => 'Fully depreciated',
      'Disposed' => 'Disposed',
      'Reversed' => 'Reversed',
      final x => x.isEmpty ? '—' : x,
    };

/// ASSET_STATUS_CLASS: (bg, fg, border).
(Color, Color, Color) assetStatusTone(Object? s) => switch (tStr(s)) {
      'Active' => (const Color(0xFFECFDF5), TColors.emerald700, TColors.emerald300),
      'FullyDepreciated' => (const Color(0xFFF0F9FF), TColors.sky700, TColors.sky300),
      'Disposed' => (TColors.amber50, TColors.amber800, TColors.amber300),
      'Reversed' => (const Color(0xFFFEF2F2), const Color(0xFFB91C1C), const Color(0xFFFCA5A5)),
      _ => (TColors.slate50, TColors.slate700, TColors.slate300),
    };

const bookValueTooltip =
    "What the capital investment is still worth on the books: what it cost, less the depreciation charged so far. It never falls below the residual value.";
const acquisitionCostLabel = 'Original acquisition cost';
const additionalCostLabel = 'Additional capitalised costs';
const totalCapitalizedCostLabel = 'Total capitalised cost';
const acquisitionCostTooltip =
    'What this capital investment was originally acquired for, including any correction made to that figure. It does not move when costs are added later.';
const additionalCostTooltip =
    'Everything capitalised into this capital investment after it was acquired — installation, improvements, upgrades. Reversed entries are excluded.';
const totalCapitalizedCostTooltip = 'Original acquisition cost plus any additional costs capitalised into this capital investment.';
const correctOriginalCostNote =
    'Use this to fix a mistake in what the capital investment was recorded as costing. It is not the same as Add cost, which records real extra money spent on it. The correction is kept on the record with its reason, and the money already recorded is adjusted — no second payment and no second expense are created.';
const correctionDepreciationNote =
    'Depreciation already posted is not changed — months that have been charged stay charged, and past profit stays as it was reported. Future months follow the corrected cost.';
const costTreatmentNote =
    "Capitalising adds the money to what the capital investment is worth and charges it to profit gradually through depreciation. Recording it as an operating expense charges the whole amount to this period's profit instead. Routine repairs, cleaning and servicing are usually operating expenses; installation, improvements and upgrades are usually capitalised.";
const costLockedByDepreciationNote =
    'Depreciation has already been posted for this capital investment, so its costs cannot be changed — every month already charged was worked out from them. Reverse the depreciation first.';
const depreciationConventionNote =
    'Depreciation is charged for the whole month an asset goes into service and for every whole month after it. Amounts are not split part-way through a month.';
const depreciationNoncashNote =
    "Depreciation reduces profit and the asset's book value. It moves no money: no cash account, no supplier and no payment are affected.";

num round2(num n) => (n * 100).round() / 100;

/// CostTypeBadge's label.
String costTypeLabel(Map c) {
  final src = tStr(c['sourceType']);
  if (src == 'OriginalCostCorrection') return 'Original cost correction';
  if (src == 'Acquisition') return 'Original acquisition';
  final cat = tStr(c['costCategory']).trim();
  return cat.isEmpty ? 'Additional cost' : cat;
}

/// A cost row can be reversed only when it is an added cost still posted.
bool costReversible(Map c) {
  final src = tStr(c['sourceType']);
  return src != 'Acquisition' && src != 'OriginalCostCorrection' && tStr(c['status']) == 'Posted';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// fmtMonthYear: "2026-09-01" → "Sep 2026".
String fmtMonthYear(Object? v) {
  final m = RegExp(r'^(\d{4})-(\d{2})').firstMatch(tStr(v));
  return m == null ? '' : '${_months[int.parse(m[2]!) - 1]} ${m[1]}';
}

typedef CorrectionPreview = ({
  num next,
  num difference,
  num newTotal,
  num newDepreciable,
  num? newMonthly,
  num newBookValue,
  num newRemaining,
  bool residualTooHigh,
  bool overDepreciated,
  bool nothingLeft,
});

/// previewCorrection: what a corrected acquisition cost would change. Null
/// for a non-positive figure or one that is the same as today's.
CorrectionPreview? previewCorrection({
  required num acquisitionCost,
  required num additionalCost,
  required num residualValue,
  required num? usefulLifeMonths,
  required num accumulatedDepreciation,
  required num? newAcquisitionCost,
}) {
  if (newAcquisitionCost == null || !newAcquisitionCost.isFinite || newAcquisitionCost <= 0) return null;
  final next = round2(newAcquisitionCost);
  final difference = round2(next - acquisitionCost);
  if (difference.abs() < 0.005) return null;
  final newTotal = round2(next + additionalCost);
  final d = round2(newTotal - residualValue);
  final newDepreciable = d > 0 ? d : 0;
  final life = usefulLifeMonths ?? 0;
  final bv = round2(newTotal - accumulatedDepreciation);
  final rem = round2(newDepreciable - accumulatedDepreciation);
  return (
    next: next,
    difference: difference,
    newTotal: newTotal,
    newDepreciable: newDepreciable,
    newMonthly: life > 0 ? round2(newDepreciable / life) : null,
    newBookValue: bv > residualValue ? bv : residualValue,
    newRemaining: rem > 0 ? rem : 0,
    residualTooHigh: residualValue > newTotal,
    overDepreciated: newDepreciable > 0 && accumulatedDepreciation >= newDepreciable,
    nothingLeft: newDepreciable <= 0,
  );
}

/// The register's search: name, number, category, location, serial, supplier.
List<Map> filterAssets(List<Map> rows, {String search = '', String status = 'all', String category = 'all'}) {
  final q = search.trim().toLowerCase();
  return rows.where((a) {
    if (status != 'all' && tStr(a['status']) != status) return false;
    if (category != 'all' && tStr(a['poultryAssetCategoryId']) != category) return false;
    if (q.isEmpty) return true;
    return ['assetName', 'assetNumber', 'categoryName', 'location', 'serialNumber', 'supplierName']
        .any((k) => tStr(a[k]).toLowerCase().contains(q));
  }).toList();
}

/// What the New investment dialog says it will record.
({num amount, num paid, num owing, num monthly}) newAssetPreview(String amount, String amountPaid, String usefulLife, String residual) {
  final a = num.tryParse(amount) ?? 0;
  final paid = amountPaid.trim().isEmpty ? a : (num.tryParse(amountPaid) ?? 0);
  final owing = a - paid > 0 ? a - paid : 0;
  final life = num.tryParse(usefulLife) ?? 0;
  final monthly = life > 0 ? round2((a - (num.tryParse(residual) ?? 0)) / life) : 0;
  return (amount: a, paid: paid, owing: owing, monthly: monthly);
}
