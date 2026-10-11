import 'package:flutter/material.dart';

import '../../../models/company.dart';
import '../../../state/session.dart';
import 'water_report_kit.dart';

// Water → Reports → Production & Inventory, one widget per
// `app/water-reports/*` page.

/// `num()` on the Raw Material Usage page: up to three decimals.
String _qty(Object? v) => wloc(v);

num _good(Map b) => b['goodBags'] != null ? wn(b['goodBags']) : wn(b['bagsProduced']) - wn(b['damagedBags']);
num _allIn(Map b) => b['allInCost'] != null ? wn(b['allInCost']) : wn(b['totalProductionCost']) + wn(b['rawMaterialCost']);

// -------------------------------------------------------- Production Report

Widget waterProductionReport(Session s, Company c) => WaterReport(
      session: s,
      company: c,
      slug: 'production-report',
      title: 'Production Report',
      description: 'Production records, output and cost analysis. Only Approved records count toward totals.',
      filename: 'water-production-report',
      load: (q) => q.list('/api/Water/production-batches', q.period),
      view: (data, q, m) {
        final rows = data as List<Map<String, dynamic>>? ?? const [];
        final approved = rows.where((b) => b['status'] == 'Approved');
        final goodBags = approved.fold<num>(0, (t, b) => t + _good(b));
        final damaged = approved.fold<num>(0, (t, b) => t + wn(b['damagedBags']));
        final cost = approved.fold<num>(0, (t, b) => t + _allIn(b));
        final avg = goodBags > 0 ? cost / goodBags : 0;
        return WaterReportView(
          tiles: [
            tile('Records', '${approved.length} / ${rows.length}'),
            tile('Good bags', wloc(goodBags), 'green'),
            tile('Damaged', wloc(damaged), 'rose'),
            tile('Avg cost/bag', m(avg)),
          ],
          columns: [
            col('Date'), col('Production'), col('Machine'), col('Product'), rcol('Produced'), rcol('Good'),
            rcol('Damaged'), rcol('Total cost'), rcol('Cost/bag'), col('Status'),
          ],
          rows: [
            for (final b in rows)
              [
                wday(b['productionDate']),
                '${b['batchNumber'] ?? '#${b['waterProductionBatchId']}'}',
                b['machineScope'] == 'AllMachines' ? 'All / Combined' : wdash(b['machineName']),
                wdash(b['productName']),
                wloc(b['bagsProduced']),
                wloc(_good(b)),
                wloc(b['damagedBags']),
                m(_allIn(b)),
                m(wn(b['costPerBag'])),
                wstr(b['status']),
              ],
          ],
          empty: 'No production records in this period.',
        );
      },
    );

// ------------------------------------------------------- Raw Material Usage

Widget waterRawMaterialUsageReport(Session s, Company c) => WaterReport(
      session: s,
      company: c,
      slug: 'raw-material-usage',
      title: 'Raw Material Usage',
      description:
          'Expected vs actual raw material consumption with variance, per material. The usage detail below is supplementary.',
      filename: 'water-raw-material-usage',
      load: (q) async => (
        await q.list('/api/Water/reports/raw-material-variance', q.period),
        await q.list('/api/Water/raw-material-usage/history', q.period),
      ),
      view: (data, q, m) {
        final d = data as (List<Map<String, dynamic>>, List<Map<String, dynamic>>)?;
        final variance = d?.$1 ?? const [];
        final usage = d?.$2 ?? const [];
        final materialColumns = [
          col('Material'), col('Category'), col('Unit'), rcol('Expected'), rcol('Actual'), rcol('Variance'), rcol('Usage count'),
        ];
        final materialRows = [
          for (final v in variance)
            [
              '${v['itemName'] ?? ''}',
              '${v['category'] ?? ''}',
              wdash(v['unitOfMeasure']),
              _qty(v['totalExpected']),
              _qty(v['totalActual']),
              _qty(v['totalVariance']),
              wloc(v['usageCount']),
            ],
        ];
        final usageColumns = [
          col('Date'), col('Batch'), col('Material'), rcol('Expected'), rcol('Actual'), rcol('Variance'), rcol('Unit cost'), rcol('Total cost'),
        ];
        final usageRows = [
          for (final r in usage)
            [
              wday(r['usedDate']),
              wdash(r['batchNumber']),
              wdash(r['itemName']),
              _qty(r['expectedQuantityUsed']),
              _qty(r['quantityUsed']),
              _qty(r['variance']),
              wn(r['unitCost']) != 0 ? m(wn(r['unitCost'])) : '—',
              wn(r['totalCost']) != 0 ? m(wn(r['totalCost'])) : '—',
            ],
        ];
        return WaterReportView(
          tiles: [
            tile('Materials', '${variance.length}'),
            tile('Expected qty', _qty(variance.fold<num>(0, (t, v) => t + wn(v['totalExpected'])))),
            tile('Actual qty', _qty(variance.fold<num>(0, (t, v) => t + wn(v['totalActual'])))),
            tile('Abs variance', _qty(variance.fold<num>(0, (t, v) => t + wn(v['totalVariance']).abs())), 'rose'),
          ],
          columns: materialColumns,
          rows: materialRows,
          sections: [
            WaterSection(heading: 'By material', columns: materialColumns, rows: materialRows, empty: 'No usage in this period.'),
            WaterSection(heading: 'Usage detail', columns: usageColumns, rows: usageRows, empty: 'No usage rows.'),
          ],
        );
      },
    );

// --------------------------------------------------- Raw Material Purchases

num _purchaseTotal(Map p) => p['totalCost'] != null ? wn(p['totalCost']) : wn(p['quantity']) * wn(p['unitCost']);

Widget waterRawMaterialPurchaseReport(Session s, Company c) => WaterReport(
      session: s,
      company: c,
      slug: 'raw-material-purchase',
      title: 'Raw Material Purchases',
      description: 'Stock-in receipts with supplier, quantity, cost and payment status.',
      filename: 'water-raw-material-purchase',
      load: (q) => q.list('/api/Water/raw-material-purchases', q.period),
      view: (data, q, m) {
        final rows = data as List<Map<String, dynamic>>? ?? const [];
        final total = rows.fold<num>(0, (t, p) => t + _purchaseTotal(p));
        final paid = rows.fold<num>(0, (t, p) => t + wn(p['amountPaid']));
        return WaterReportView(
          tiles: [
            tile('Purchases', wloc(rows.length)),
            tile('Total cost', m(total)),
            tile('Paid', m(paid), 'green'),
            tile('Outstanding', m(total - paid), 'rose'),
          ],
          columns: [
            col('Date'), col('Material'), col('Supplier'), rcol('Quantity'), rcol('Unit cost'), rcol('Total cost'),
            rcol('Paid'), rcol('Balance'), col('Method'),
          ],
          rows: [
            for (final p in rows)
              [
                wday(p['purchaseDate']),
                wstr(p['itemName'] ?? p['waterRawMaterialItemId']),
                wdash(p['supplierName']),
                wloc(p['quantity']),
                m(wn(p['unitCost'])),
                m(_purchaseTotal(p)),
                m(wn(p['amountPaid'])),
                m(_purchaseTotal(p) - wn(p['amountPaid'])),
                wdash(p['paymentMethod']),
              ],
          ],
          empty: 'No purchases in this period.',
        );
      },
    );

// --------------------------------------------------------- Inventory / Stock

Widget waterInventoryReport(Session s, Company c) => WaterReport(
      session: s,
      company: c,
      slug: 'inventory-report',
      title: 'Inventory / Stock',
      description: 'Current stock position for finished products and raw materials.',
      filename: 'water-inventory-report',
      dated: false,
      load: (q) async {
        final products = await q.listOrEmpty('/api/Water/products');
        final raws = await q.listOrEmpty('/api/Water/raw-material-items');
        final rows = <Map<String, dynamic>>[
          for (final p in products)
            {
              'name': '${p['name'] ?? ''}',
              'type': p['productType'] ?? 'FinishedGood',
              'unit': p['unit'] ?? 'bag',
              'stock': wn(p['stockOnHand']),
              'minAlert': null,
              'unitCost': p['unitPrice'],
              'status': wn(p['stockOnHand']) <= 0 ? 'Out' : 'OK',
            },
          for (final r in raws)
            {
              'name': '${r['itemName'] ?? ''}',
              'type': 'RawMaterial',
              'unit': r['unitOfMeasure'] ?? '—',
              'stock': wn(r['currentQuantity']),
              'minAlert': r['minimumStockAlert'] == null ? null : wn(r['minimumStockAlert']),
              'unitCost': r['lastUnitCost'],
              'status': wn(r['currentQuantity']) <= 0
                  ? 'Out'
                  : (r['minimumStockAlert'] != null && wn(r['currentQuantity']) <= wn(r['minimumStockAlert']))
                      ? 'Low'
                      : 'OK',
            },
        ]..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
        return rows;
      },
      view: (data, q, m) {
        final rows = data as List<Map<String, dynamic>>? ?? const [];
        final value = rows.fold<num>(0, (t, r) => t + (r['unitCost'] != null ? wn(r['stock']) * wn(r['unitCost']) : 0));
        return WaterReportView(
          tiles: [
            tile('Items', wloc(rows.length)),
            tile('Low stock', '${rows.where((r) => r['status'] == 'Low').length}', 'rose'),
            tile('Out of stock', '${rows.where((r) => r['status'] == 'Out').length}', 'rose'),
            tile('Stock value', m(value)),
          ],
          columns: [col('Item'), col('Type'), col('Unit'), rcol('Stock'), rcol('Min alert'), rcol('Unit cost'), rcol('Stock value'), col('Status')],
          rows: [
            for (final r in rows)
              [
                '${r['name']}',
                '${r['type']}',
                '${r['unit']}',
                wloc(r['stock']),
                r['minAlert'] == null ? '—' : wstr(r['minAlert']),
                r['unitCost'] != null ? m(wn(r['unitCost'])) : '—',
                r['unitCost'] != null ? m(wn(r['stock']) * wn(r['unitCost'])) : '—',
                '${r['status']}',
              ],
          ],
          empty: 'No inventory rows yet.',
        );
      },
    );

// ------------------------------------------------------------ Stock Movement

Widget waterStockMovementReport(Session s, Company c) => WaterReport(
      session: s,
      company: c,
      slug: 'stock-movement',
      title: 'Stock Movement',
      description: 'Inventory transactions for finished products in the selected period.',
      filename: 'water-stock-movement',
      load: (q) async {
        final all = await q.list('/api/Water/stock/transactions');
        return [
          for (final t in all)
            if (wday(t['createdDate']).compareTo(q.from) >= 0 && wday(t['createdDate']).compareTo(q.to) <= 0) t,
        ];
      },
      view: (data, q, m) {
        final rows = data as List<Map<String, dynamic>>? ?? const [];
        final inflow = rows.where((r) => wn(r['quantity']) > 0).fold<num>(0, (t, r) => t + wn(r['quantity']));
        final outflow = rows.where((r) => wn(r['quantity']) < 0).fold<num>(0, (t, r) => t + wn(r['quantity']));
        final net = inflow + outflow;
        return WaterReportView(
          tiles: [
            tile('Movements', wloc(rows.length)),
            tile('In', wloc(inflow), 'green'),
            tile('Out', wloc(outflow.abs()), 'rose'),
            tile('Net change', wloc(net), net >= 0 ? 'green' : 'rose'),
          ],
          columns: [col('Date'), col('Product'), col('Type'), rcol('Quantity'), rcol('Unit cost'), col('Note')],
          rows: [
            for (final r in rows)
              [
                wday(r['createdDate']),
                '${r['productName'] ?? '#${r['waterProductId']}'}',
                wdash(r['txnType']),
                wloc(r['quantity']),
                r['unitCost'] != null ? m(wn(r['unitCost'])) : '—',
                wdash(r['note']),
              ],
          ],
          empty: 'No stock movements in this period.',
        );
      },
    );

// ------------------------------------------------------- Product Performance

Widget waterProductPerformanceReport(Session s, Company c) => WaterReport(
      session: s,
      company: c,
      slug: 'product-performance',
      title: 'Product Performance',
      description: 'Production output + cost per product (revenue rollup pending server-side aggregation).',
      filename: 'water-product-performance',
      load: (q) async {
        final products = await q.listOrEmpty('/api/Water/products');
        // The page also loads sales, then deliberately ignores them (no sale
        // items yet), so they are not fetched here.
        final batches = await q.listOrEmpty('/api/Water/production-batches', q.period);
        final map = <int, Map<String, dynamic>>{
          for (final p in products)
            wn(p['waterProductId']).toInt(): {
              'name': '${p['name'] ?? ''}',
              'type': p['productType'] ?? 'FinishedGood',
              'produced': 0,
              'productionCost': 0,
              'costPerBag': 0,
              'stockOnHand': wn(p['stockOnHand']),
            },
        };
        for (final b in batches) {
          if (b['status'] != 'Approved' || b['waterProductId'] == null) continue;
          final row = map[wn(b['waterProductId']).toInt()];
          if (row == null) continue;
          row['produced'] = wn(row['produced']) + _good(b);
          row['productionCost'] = wn(row['productionCost']) + _allIn(b);
        }
        for (final r in map.values) {
          if (wn(r['produced']) > 0) r['costPerBag'] = wn(r['productionCost']) / wn(r['produced']);
        }
        return map.values.where((r) => wn(r['produced']) > 0 || wn(r['stockOnHand']) != 0).toList();
      },
      view: (data, q, m) {
        final rows = data as List<Map<String, dynamic>>? ?? const [];
        return WaterReportView(
          tiles: [
            tile('Products', '${rows.length}'),
            tile('Total produced', wloc(rows.fold<num>(0, (t, r) => t + wn(r['produced']))), 'green'),
            tile('Total cost', m(rows.fold<num>(0, (t, r) => t + wn(r['productionCost'])))),
          ],
          columns: [col('Product'), col('Type'), rcol('Good produced'), rcol('Production cost'), rcol('Cost/bag'), rcol('Stock')],
          rows: [
            for (final r in rows)
              [
                '${r['name']}',
                '${r['type']}',
                wloc(r['produced']),
                m(wn(r['productionCost'])),
                m(wn(r['costPerBag'])),
                wloc(r['stockOnHand']),
              ],
          ],
          empty: 'No production for any product in this period.',
        );
      },
    );
