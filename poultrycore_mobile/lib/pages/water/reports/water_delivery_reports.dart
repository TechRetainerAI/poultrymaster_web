import 'package:flutter/material.dart';

import '../../../models/company.dart';
import '../../../state/session.dart';
import 'water_report_kit.dart';

// Water → Reports: the Delivery & Operations column (bar the Operational
// dashboard) plus the three single-table Financial reports — Closing,
// Expense and Supplier Activity. One widget per `app/water-reports/*` page.

// ------------------------------------------------------------ Closing Report

Widget waterClosingReport(Session s, Company c) => WaterReport(
      session: s,
      company: c,
      slug: 'closing-report',
      title: 'Closing Report',
      description: 'Daily closings with submission + reopen history.',
      filename: 'water-closing-report',
      load: (q) => q.list('/api/Water/daily-closings', q.period),
      view: (data, q, m) {
        final rows = data as List<Map<String, dynamic>>? ?? const [];
        final approved = rows.where((c) => c['status'] == 'Approved');
        return WaterReportView(
          tiles: [
            tile('Closings', '${approved.length} / ${rows.length}'),
            tile('Income', m(approved.fold<num>(0, (t, c) => t + wn(c['totalIncome']))), 'green'),
            tile('Expenses', m(approved.fold<num>(0, (t, c) => t + wn(c['totalExpenses']))), 'rose'),
            tile('Cash at hand', m(approved.fold<num>(0, (t, c) => t + wn(c['cashAtHand'])))),
          ],
          columns: [
            col('Date'), rcol('Produced'), rcol('Sold'), rcol('Income'), rcol('Expenses'), rcol('Cash at hand'),
            col('Submitted by'), col('Status'), col('Notes'),
          ],
          rows: [
            for (final c in rows)
              [
                wday(c['closingDate']),
                wloc(c['bagsProduced']),
                wloc(c['bagsSold']),
                m(wn(c['totalIncome'])),
                m(wn(c['totalExpenses'])),
                m(wn(c['cashAtHand'])),
                wdash(c['submittedBy'] ?? c['createdBy']),
                c['supersededByClosingId'] != null ? '${c['status']} → #${c['supersededByClosingId']}' : wstr(c['status']),
                '${c['reopenReason'] ?? ''}'.isNotEmpty ? 'Reopened: ${c['reopenReason']}' : wdash(c['managerNotes']),
              ],
          ],
          empty: 'No closings in this period.',
        );
      },
    );

// ------------------------------------------------------------ Expense Report

Widget waterExpenseReport(Session s, Company c) => WaterReport(
      session: s,
      company: c,
      slug: 'expense-report',
      title: 'Expense Report',
      description: 'Expenses grouped by category (authoritative report). The detail list below is supplementary.',
      filename: 'water-expense-report',
      load: (q) async => (
        await q.list('/api/Water/reports/expense-by-category', q.period),
        await q.list('/api/Water/expenses', q.period),
      ),
      view: (data, q, m) {
        final d = data as (List<Map<String, dynamic>>, List<Map<String, dynamic>>)?;
        final cats = [...?d?.$1]..sort((a, b) => wn(b['totalAmount']).compareTo(wn(a['totalAmount'])));
        final rows = d?.$2 ?? const [];
        final columns = [col('Category'), rcol('Count'), rcol('Total')];
        final catRows = [
          for (final c in cats) ['${c['categoryName'] ?? ''}', wloc(c['expenseCount']), m(wn(c['totalAmount']))],
        ];
        return WaterReportView(
          tiles: [
            tile('Categories', '${cats.length}'),
            tile('Expense count', wloc(cats.fold<num>(0, (t, c) => t + wn(c['expenseCount'])))),
            tile('Total', m(cats.fold<num>(0, (t, c) => t + wn(c['totalAmount']))), 'rose'),
          ],
          columns: columns,
          rows: catRows,
          sections: [
            WaterSection(heading: 'By category', columns: columns, rows: catRows, empty: 'No expenses in this period.', cards: false),
            WaterSection(
              heading: 'Details',
              columns: [col('Date'), col('Category'), col('Description'), col('Method'), col('Source'), rcol('Amount'), col('Status')],
              rows: [
                for (final e in rows)
                  [
                    wday(e['expenseDate']),
                    wdash(e['categoryName']),
                    wdash(e['description']),
                    wdash(e['paymentMethod']),
                    e['linkedWaterProductionBatchId'] != null && e['linkedWaterProductionBatchId'] != 0 ? 'Production' : 'Manual',
                    m(wn(e['amount'])),
                    wdash(e['status']),
                  ],
              ],
              empty: 'No expenses in this period.',
            ),
          ],
        );
      },
    );

// --------------------------------------------------------- Supplier Activity

Widget waterSupplierActivityReport(Session s, Company c) => WaterReport(
      session: s,
      company: c,
      slug: 'supplier-activity',
      title: 'Supplier Activity Report',
      description: 'Purchases, expenses paid, outstanding balances, and last activity per supplier.',
      filename: 'water-supplier-activity',
      load: (q) => q.list('/api/Water/reports/supplier-activity', q.period),
      view: (data, q, m) {
        final rows = data as List<Map<String, dynamic>>? ?? const [];
        String day(Object? v) => '${v ?? ''}'.isEmpty ? '—' : '$v'.split('T').first;
        return WaterReportView(
          tiles: [
            tile('Suppliers', '${rows.length}'),
            tile('Active (in range)', '${rows.where((r) => wn(r['purchaseCount']) > 0 || wn(r['expenseCount']) > 0).length}'),
            tile('Total purchases', m(rows.fold<num>(0, (t, r) => t + wn(r['totalPurchaseAmount'])))),
            tile('Total paid', m(rows.fold<num>(0, (t, r) => t + wn(r['totalExpenseAmount'])))),
            tile('Outstanding', m(rows.fold<num>(0, (t, r) => t + wn(r['outstandingBalance']))), 'rose'),
          ],
          columns: [
            col('Supplier'), col('Type'), col('Phone'), rcol('Purchases'), rcol('Purchase total'), rcol('Expenses paid'),
            rcol('Outstanding'), col('Last purchase'), col('Last expense'),
          ],
          rows: [
            for (final r in rows)
              [
                '${r['supplierName'] ?? ''}',
                wdash(r['supplierType']),
                wdash(r['phone']),
                wstr(r['purchaseCount']),
                m(wn(r['totalPurchaseAmount'])),
                m(wn(r['totalExpenseAmount'])),
                m(wn(r['outstandingBalance'])),
                day(r['lastPurchaseDate']),
                day(r['lastExpenseDate']),
              ],
          ],
          empty: 'No suppliers yet. Add some from the Suppliers page or Setup > Suppliers tab.',
          landscape: true,
        );
      },
    );

// ------------------------------------------------------- Delivery Run Report

Widget waterDeliveryRunReport(Session s, Company c) => WaterReport(
      session: s,
      company: c,
      slug: 'delivery-run-report',
      title: 'Delivery Run Report',
      description: 'Vehicle loadings + their reconciliation status.',
      filename: 'water-delivery-run-report',
      load: (q) async => (
        await q.list('/api/Water/vehicle-loadings', q.period),
        await q.list('/api/Water/driver-returns', q.period),
      ),
      view: (data, q, m) {
        final d = data as (List<Map<String, dynamic>>, List<Map<String, dynamic>>)?;
        final loadings = d?.$1 ?? const [];
        final returns = d?.$2 ?? const [];
        num sumR(String k) => returns.fold<num>(0, (t, r) => t + wn(r[k]));
        final cash = sumR('cashCollected') + sumR('moMoCollected') + sumR('bankCollected');
        Map? retFor(Map l) => returns.where((x) => x['waterVehicleLoadingId'] == l['waterVehicleLoadingId']).firstOrNull;
        return WaterReportView(
          tiles: [
            tile('Runs', '${loadings.where((l) => l['status'] == 'Reconciled').length} / ${loadings.length}'),
            tile('Bags sold', wloc(sumR('bagsSold')), 'green'),
            tile('Bags returned', wloc(sumR('bagsReturned'))),
            tile('Cash collected', m(cash), 'green'),
          ],
          columns: [
            col('Date'), col('Driver'), col('Vehicle'), col('Route'), rcol('Loaded'), rcol('Sold'), rcol('Returned'),
            rcol('Damaged'), rcol('Expected'), rcol('Shortage'), col('Status'),
          ],
          rows: [
            for (final l in loadings)
              () {
                final r = retFor(l);
                return [
                  wday(l['loadDate']),
                  wdash(l['driverName']),
                  wdash(l['vehicleName']),
                  wdash(l['routeName']),
                  wloc(l['bagsLoaded']),
                  wloc(r?['bagsSold']),
                  wloc(r?['bagsReturned']),
                  wloc(r?['bagsDamaged']),
                  m(wn(l['expectedCash'])),
                  m(wn(r?['shortageAmount'])),
                  wstr(l['status']),
                ];
              }(),
          ],
          empty: 'No runs in this period.',
          landscape: true,
        );
      },
    );

// ----------------------------------------------------- Driver Accountability

Widget waterDriverAccountabilityReport(Session s, Company c) => WaterReport(
      session: s,
      company: c,
      slug: 'driver-accountability',
      title: 'Driver Accountability',
      description: 'Per-driver bags loaded/sold/returned, expected vs accounted revenue, and shortages.',
      filename: 'water-driver-accountability',
      load: (q) => q.list('/api/Water/reports/driver-reconciliation', q.period),
      view: (data, q, m) {
        final rows = data as List<Map<String, dynamic>>? ?? const [];
        num sum(String k) => rows.fold<num>(0, (t, r) => t + wn(r[k]));
        return WaterReportView(
          tiles: [
            tile('Drivers', '${rows.length}'),
            tile('Expected revenue', m(sum('expectedRevenue'))),
            tile('Accounted for', m(sum('actualAccountedFor')), 'green'),
            tile('Total shortages', m(sum('totalShortages')), 'rose'),
          ],
          columns: [
            col('Driver'), rcol('Loaded'), rcol('Sold'), rcol('Returned'), rcol('Lost'), rcol('Expected'), rcol('Accounted'),
            rcol('Shortages'), rcol('Occurrences'),
          ],
          rows: [
            for (final r in rows)
              [
                '${r['driverName'] ?? ''}',
                wloc(r['totalBagsLoaded']),
                wloc(r['totalBagsSold']),
                wloc(r['totalBagsReturned']),
                wloc(r['totalBagsLost']),
                m(wn(r['expectedRevenue'])),
                m(wn(r['actualAccountedFor'])),
                m(wn(r['totalShortages'])),
                wstr(r['shortageOccurrences'] ?? 0),
              ],
          ],
          empty: 'No driver activity in this period.',
          landscape: true,
        );
      },
    );

// --------------------------------------------------------- Route Performance

Widget waterRoutePerformanceReport(Session s, Company c) => WaterReport(
      session: s,
      company: c,
      slug: 'route-performance',
      title: 'Route Performance',
      description: 'Per-route bags, revenue, shortages/overages and net income.',
      filename: 'water-route-performance',
      load: (q) => q.list('/api/Water/reports/route-profitability', q.period),
      view: (data, q, m) {
        final rows = data as List<Map<String, dynamic>>? ?? const [];
        num sum(String k) => rows.fold<num>(0, (t, r) => t + wn(r[k]));
        final net = sum('netRouteIncome');
        return WaterReportView(
          tiles: [
            tile('Routes', '${rows.length}'),
            tile('Revenue', m(sum('totalRevenue')), 'green'),
            tile('Net income', m(net), net >= 0 ? 'green' : 'rose'),
            tile('Shortages', m(sum('totalShortages')), 'rose'),
          ],
          columns: [
            col('Route'), rcol('Loaded'), rcol('Sold'), rcol('Returned'), rcol('Lost'), rcol('Revenue'), rcol('Shortages'),
            rcol('Overages'), rcol('Net income'),
          ],
          rows: [
            for (final r in rows)
              [
                '${r['routeName'] ?? ''}',
                wloc(r['totalBagsLoaded']),
                wloc(r['totalBagsSold']),
                wloc(r['totalBagsReturned']),
                wloc(r['totalBagsLost']),
                m(wn(r['totalRevenue'])),
                m(wn(r['totalShortages'])),
                m(wn(r['totalOverages'])),
                m(wn(r['netRouteIncome'])),
              ],
          ],
          empty: 'No route activity in this period.',
          landscape: true,
        );
      },
    );

// ---------------------------------------------------------- Driver Collection

Widget waterDriverCollectionReport(Session s, Company c) => WaterReport(
      session: s,
      company: c,
      slug: 'driver-collection',
      title: 'Driver Collection',
      description: 'Per-driver cash/MoMo/bank collections, credit, shortages, plus per-product detail.',
      filename: 'water-driver-collection',
      filters: [
        WaterFilterDef(
          key: 'driver',
          label: 'Driver',
          initial: 'all',
          summaryLabel: 'Driver',
          options: (q) async => [
            ('all', 'All drivers'),
            for (final d in await q.listOrEmpty('/api/Water/drivers')) ('${d['waterDriverId']}', '${d['driverName'] ?? ''}'),
          ],
        ),
      ],
      load: (q) async {
        final id = q.filters['driver'];
        final res = await q.get('/api/Water/reports/driver-collection', {
          ...q.period,
          if (id != null && id != 'all') 'waterDriverId': id,
        });
        final drivers = await q.listOrEmpty('/api/Water/drivers');
        List<Map<String, dynamic>> part(String k) => [
              for (final r in (res is Map && res[k] is List ? res[k] as List : const []))
                if (r is Map) Map<String, dynamic>.from(r),
            ];
        final name = id == null || id == 'all'
            ? 'All drivers'
            : '${drivers.where((d) => '${d['waterDriverId']}' == id).firstOrNull?['driverName'] ?? '#$id'}';
        return (part('totals'), part('detail'), name);
      },
      view: (data, q, m) {
        final d = data as (List<Map<String, dynamic>>, List<Map<String, dynamic>>, String)?;
        final totals = d?.$1 ?? const [];
        final detail = d?.$2 ?? const [];
        final name = d?.$3 ?? 'All drivers';
        num sum(String k) => totals.fold<num>(0, (t, r) => t + wn(r[k]));
        final totalsColumns = [
          col('Driver'), rcol('Runs'), rcol('Reconciled'), rcol('Cash'), rcol('MoMo'), rcol('Bank'), rcol('Credit'),
          rcol('Shortage'), rcol('Overage'),
        ];
        final totalsRows = [
          for (final t in totals)
            [
              wdash(t['driverName']),
              wstr(t['deliveryRuns'] ?? 0),
              wstr(t['reconciledRuns'] ?? 0),
              m(wn(t['cashCollected'])),
              m(wn(t['moMoCollected'])),
              m(wn(t['bankCollected'])),
              m(wn(t['creditSales'])),
              m(wn(t['shortage'])),
              m(wn(t['overage'])),
            ],
        ];
        return WaterReportView(
          tiles: [
            tile('Drivers', '${totals.length}'),
            tile('Collected', m(sum('cashCollected') + sum('moMoCollected') + sum('bankCollected')), 'green'),
            tile('Credit sales', m(sum('creditSales'))),
            tile('Shortages', m(sum('shortage')), 'rose'),
          ],
          columns: totalsColumns,
          rows: totalsRows,
          subtitle: 'Driver: $name',
          landscape: true,
          activeFilters: [('Driver', name)],
          sections: [
            WaterSection(heading: 'Totals by driver', columns: totalsColumns, rows: totalsRows, empty: 'No collections in this period.'),
            WaterSection(
              heading: 'Detail by product',
              columns: [
                col('Driver'), col('Product'), rcol('Loaded'), rcol('Sold'), rcol('Returned'), rcol('Damaged'),
                rcol('Expected cash'), rcol('Sales value'),
              ],
              rows: [
                for (final r in detail)
                  [
                    wdash(r['driverName']),
                    wdash(r['productName']),
                    wloc(r['bagsLoaded']),
                    wloc(r['bagsSold']),
                    wloc(r['bagsReturned']),
                    wloc(r['bagsDamaged']),
                    m(wn(r['expectedCash'])),
                    m(wn(r['salesValue'])),
                  ],
              ],
              empty: 'No detail rows.',
            ),
          ],
        );
      },
    );

// -------------------------------------------------------------- Vehicle Usage

Widget waterVehicleUsageReport(Session s, Company c) => WaterReport(
      session: s,
      company: c,
      slug: 'vehicle-usage',
      title: 'Vehicle Usage',
      filename: 'water-vehicle-usage',
      load: (q) async {
        final loadings = await q.list('/api/Water/vehicle-loadings', q.period);
        final returns = await q.list('/api/Water/driver-returns', q.period);
        final vehicles = await q.listOrEmpty('/api/Water/vehicles');
        final map = <int, Map<String, dynamic>>{
          for (final v in vehicles)
            wn(v['waterVehicleId']).toInt(): {
              'vehicleName': '${v['vehicleName'] ?? ''}',
              'vehicleType': '${v['vehicleType'] ?? ''}',
              'runs': 0,
              'loaded': 0,
              'sold': 0,
              'damaged': 0,
              'shortage': 0,
            },
        };
        for (final l in loadings) {
          final row = map[wn(l['waterVehicleId']).toInt()];
          if (row == null) continue;
          row['runs'] = wn(row['runs']) + 1;
          row['loaded'] = wn(row['loaded']) + wn(l['bagsLoaded']);
        }
        for (final ret in returns) {
          final parent = loadings.where((l) => l['waterVehicleLoadingId'] == ret['waterVehicleLoadingId']).firstOrNull;
          if (parent == null) continue;
          final row = map[wn(parent['waterVehicleId']).toInt()];
          if (row == null) continue;
          row['sold'] = wn(row['sold']) + wn(ret['bagsSold']);
          row['damaged'] = wn(row['damaged']) + wn(ret['bagsDamaged']);
          row['shortage'] = wn(row['shortage']) + wn(ret['shortageAmount']);
        }
        return map.values.where((r) => wn(r['runs']) > 0).toList()..sort((a, b) => wn(b['runs']).compareTo(wn(a['runs'])));
      },
      view: (data, q, m) {
        final rows = data as List<Map<String, dynamic>>? ?? const [];
        return WaterReportView(
          tiles: [
            tile('Active vehicles', '${rows.length}'),
            tile('Total runs', wloc(rows.fold<num>(0, (t, r) => t + wn(r['runs'])))),
            tile('Total loaded', wloc(rows.fold<num>(0, (t, r) => t + wn(r['loaded'])))),
          ],
          columns: [col('Vehicle'), col('Type'), rcol('Runs'), rcol('Loaded'), rcol('Sold'), rcol('Damaged'), rcol('Shortage')],
          rows: [
            for (final r in rows)
              [
                '${r['vehicleName']}',
                '${r['vehicleType']}',
                wstr(r['runs']),
                wloc(r['loaded']),
                wloc(r['sold']),
                wloc(r['damaged']),
                m(wn(r['shortage'])),
              ],
          ],
          empty: 'No vehicle activity in this period.',
        );
      },
    );

// --------------------------------------------------------------- Loss Report

Widget waterLossReport(Session s, Company c) => WaterReport(
      session: s,
      company: c,
      slug: 'loss-report',
      title: 'Loss Report',
      description: 'Damaged bags, rejected sachets, manual losses. Only Approved records count toward totals.',
      filename: 'water-loss-report',
      load: (q) async {
        final manual = await q.listOrEmpty('/api/Water/loss-records', q.period);
        final production = await q.listOrEmpty('/api/Water/production-losses', q.period);
        return <Map<String, dynamic>>[
          for (final r in manual)
            {
              'source': 'Manual',
              'date': wday(r['lossDate']),
              'type': r['lossType'] ?? '—',
              'product': r['productName'] ?? '—',
              'bags': wn(r['quantityBags']),
              'sachets': wn(r['quantitySachets']),
              'value': wn(r['estimatedValue']),
              'reason': r['reason'] ?? '—',
              'status': r['status'] ?? '—',
            },
          for (final r in production)
            {
              'source': 'Production',
              'date': wday(r['lossDate']),
              'type': r['lossType'] ?? 'ProductionDamage',
              'product': r['productName'] ?? '—',
              'bags': wn(r['bagsLost']),
              'sachets': wn(r['sachetsLost']),
              'value': wn(r['totalValue']),
              'reason': r['reason'] ?? r['batchNumber'] ?? '—',
              'status': r['status'] ?? 'Approved',
            },
        ]..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
      },
      view: (data, q, m) {
        final rows = data as List<Map<String, dynamic>>? ?? const [];
        final approved = rows.where((r) => r['status'] == 'Approved');
        return WaterReportView(
          tiles: [
            tile('Records', '${approved.length} / ${rows.length}'),
            tile('Bags lost', wloc(approved.fold<num>(0, (t, r) => t + wn(r['bags']))), 'rose'),
            tile('Sachets lost', wloc(approved.fold<num>(0, (t, r) => t + wn(r['sachets']))), 'rose'),
            tile('Total value', m(approved.fold<num>(0, (t, r) => t + wn(r['value']))), 'rose'),
          ],
          columns: [
            col('Date'), col('Source'), col('Type'), col('Product'), rcol('Bags'), rcol('Sachets'), rcol('Value'),
            col('Reason'), col('Status'),
          ],
          rows: [
            for (final r in rows)
              [
                '${r['date']}',
                '${r['source']}',
                '${r['type']}',
                '${r['product']}',
                wloc(r['bags']),
                wloc(r['sachets']),
                m(wn(r['value'])),
                '${r['reason']}',
                '${r['status']}',
              ],
          ],
          empty: 'No losses in this period.',
        );
      },
    );
