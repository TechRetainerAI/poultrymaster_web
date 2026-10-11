import 'package:flutter/material.dart';

import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../poultry/reports/report_widgets.dart';
import 'water_report_kit.dart';

// Water → Reports → Sales & Customers, one widget per `app/water-reports/*`
// page: Sales Report, Payments Received, Customer Balances, Customer Sales
// History and Top Customers.

// ------------------------------------------------------------ Sales Report

Widget waterSalesReport(Session s, Company c) => WaterReport(
      session: s,
      company: c,
      slug: 'sales-report',
      title: 'Sales Report',
      description: "All sales in the selected period. Totals respect the company's currency settings.",
      filename: 'water-sales-report',
      load: (q) async {
        // listWaterSales returns the full list; filter client-side.
        final all = await q.list('/api/Water/sales');
        return [
          for (final r in all)
            if (wday(r['saleDate']).compareTo(q.from) >= 0 && wday(r['saleDate']).compareTo(q.to) <= 0) r,
        ];
      },
      view: (data, q, m) {
        final rows = data as List<Map<String, dynamic>>? ?? const [];
        final total = rows.fold<num>(0, (t, r) => t + wn(r['totalAmount']));
        final paid = rows.fold<num>(0, (t, r) => t + wn(r['amountPaid']));
        return WaterReportView(
          tiles: [
            tile('Sales count', wloc(rows.length)),
            tile('Total amount', m(total)),
            tile('Amount paid', m(paid), 'green'),
            tile('Outstanding', m(total - paid), 'rose'),
          ],
          columns: [col('Date'), col('Sale #'), col('Customer'), col('Source'), rcol('Total'), rcol('Paid'), rcol('Balance'), col('Status')],
          rows: [
            for (final r in rows)
              [
                wday(r['saleDate']),
                wstr(r['waterSaleId']),
                wdash(r['customerName'] ?? r['waterCustomerId']),
                '${r['sourceType'] ?? 'Manual'}',
                m(wn(r['totalAmount'])),
                m(wn(r['amountPaid'])),
                m(wn(r['totalAmount']) - wn(r['amountPaid'])),
                wdash(r['status']),
              ],
          ],
          empty: 'No sales in this period.',
        );
      },
    );

// ------------------------------------------------------- Payments Received

Widget waterPaymentsReceivedReport(Session s, Company c) => WaterReport(
      session: s,
      company: c,
      slug: 'payments-received',
      title: 'Payments Received',
      description: 'Customer collections by date, method and source.',
      filename: 'water-payments-received',
      load: (q) async {
        // One row per payment (migration 227's grouped view). Reversed
        // payments never stayed, so a collections report leaves them out.
        final all = await q.list('/api/Water/customer-payments', {'from': q.from, 'to': q.to});
        return [for (final r in all) if ('${r['status'] ?? 'Posted'}' != 'Reversed') r];
      },
      view: (data, q, m) {
        final rows = data as List<Map<String, dynamic>>? ?? const [];
        final total = rows.fold<num>(0, (t, r) => t + wn(r['totalAmount']));
        final byMethod = <String, num>{};
        for (final r in rows) {
          final k = '${r['paymentMethod'] ?? 'Other'}';
          byMethod[k] = (byMethod[k] ?? 0) + wn(r['totalAmount']);
        }
        final sales = rows.fold<num>(0, (t, r) => t + wn(r['allocationCount']));
        String appliedTo(Map r) {
          final n = r['allocationCount'] == null ? 1 : wn(r['allocationCount']);
          return '${wstr(n)} sale${n == 1 ? '' : 's'}';
        }

        String paymentRef(Map r) {
          final n = '${r['paymentNumber'] ?? ''}'.trim();
          if (n.isNotEmpty) return n;
          final id = '${r['paymentId'] ?? ''}';
          return '#${id.length > 8 ? id.substring(0, 8) : id}';
        }

        final detailColumns = [col('Date'), col('Payment'), col('Customer'), col('Applied to'), col('Method'), col('Reference'), rcol('Amount')];
        final detailRows = [
          for (final r in rows)
            [
              wday(r['paymentDate']),
              paymentRef(r),
              wdash(r['partyName']),
              appliedTo(r),
              wdash(r['paymentMethod']),
              wdash(r['reference']),
              m(wn(r['totalAmount'])),
            ],
        ];
        final methods = byMethod.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        return WaterReportView(
          tiles: [
            tile('Payments', wloc(rows.length)),
            tile('Total collected', m(total), 'green'),
            tile('Sales settled', wloc(sales)),
            tile('Methods used', '${byMethod.length}'),
          ],
          columns: detailColumns,
          rows: detailRows,
          sections: [
            WaterSection(
              heading: 'By method',
              columns: [col('Method'), rcol('Total')],
              rows: [for (final e in methods) [e.key, m(e.value)]],
              empty: 'No payments.',
              cards: false,
            ),
            WaterSection(heading: 'Details', columns: detailColumns, rows: detailRows, empty: 'No payments in this period.'),
          ],
        );
      },
    );

// ------------------------------------------------------- Customer Balances

Widget waterCustomerBalancesReport(Session s, Company c) => WaterReport(
      session: s,
      company: c,
      slug: 'customer-balances',
      title: 'Customer Balances / Receivables',
      description: 'Sales − payments per customer, with the most-owing at the top.',
      filename: 'water-customer-balances',
      dated: false,
      load: (q) async {
        final customers = await q.listOrEmpty('/api/Water/customers');
        final sales = await q.listOrEmpty('/api/Water/sales');
        final payments = await q.listOrEmpty('/api/Water/payments');
        final by = <int, Map<String, dynamic>>{};
        for (final c in customers) {
          final id = wn(c['waterCustomerId']).toInt();
          by[id] = {'name': c['name'] ?? '#$id', 'totalSales': 0, 'totalPaid': 0, 'outstanding': 0, 'lastSale': null, 'lastPayment': null};
        }
        // WaterPayment carries waterSaleId, not the customer.
        final saleToCustomer = <int, int>{};
        for (final s in sales) {
          if (s['status'] == 'Cancelled' || s['waterCustomerId'] == null) continue;
          final cid = wn(s['waterCustomerId']).toInt();
          saleToCustomer[wn(s['waterSaleId']).toInt()] = cid;
          final r = by[cid];
          if (r == null) continue;
          r['totalSales'] = wn(r['totalSales']) + wn(s['totalAmount']);
          r['totalPaid'] = wn(r['totalPaid']) + wn(s['amountPaid']);
          final d = wday(s['saleDate']);
          if (r['lastSale'] == null || d.compareTo(r['lastSale'] as String) > 0) r['lastSale'] = d;
        }
        for (final p in payments) {
          final cid = saleToCustomer[wn(p['waterSaleId']).toInt()];
          final r = cid == null ? null : by[cid];
          if (r == null) continue;
          final d = wday(p['paymentDate']);
          if (r['lastPayment'] == null || d.compareTo(r['lastPayment'] as String) > 0) r['lastPayment'] = d;
        }
        for (final r in by.values) {
          r['outstanding'] = wn(r['totalSales']) - wn(r['totalPaid']);
        }
        return by.values.where((r) => wn(r['totalSales']) != 0 || wn(r['outstanding']) != 0).toList()
          ..sort((a, b) => wn(b['outstanding']).compareTo(wn(a['outstanding'])));
      },
      view: (data, q, m) {
        final rows = data as List<Map<String, dynamic>>? ?? const [];
        return WaterReportView(
          tiles: [
            tile('Customers', '${rows.length}'),
            tile('Customers owing', '${rows.where((r) => wn(r['outstanding']) > 0).length}', 'rose'),
            tile('Total outstanding', m(rows.fold<num>(0, (t, r) => t + (wn(r['outstanding']) > 0 ? wn(r['outstanding']) : 0))), 'rose'),
            tile('Total sales', m(rows.fold<num>(0, (t, r) => t + wn(r['totalSales'])))),
          ],
          columns: [col('Customer'), rcol('Total sales'), rcol('Total paid'), rcol('Outstanding'), col('Last sale'), col('Last payment')],
          rows: [
            for (final r in rows)
              [
                '${r['name']}',
                m(wn(r['totalSales'])),
                m(wn(r['totalPaid'])),
                m(wn(r['outstanding'])),
                wdash(r['lastSale']),
                wdash(r['lastPayment']),
              ],
          ],
          empty: 'No customer activity yet.',
        );
      },
    );

// -------------------------------------------------- Customer Sales History

Widget waterCustomerHistoryReport(Session s, Company c) => WaterReport(
      session: s,
      company: c,
      slug: 'customer-history',
      title: 'Customer Sales History',
      description: 'Pick a customer to see their sales + payment timeline.',
      filename: 'water-customer-history',
      // The page opens on the last 90 days (its own defaultFrom).
      initialFrom: wdaysAgo(90),
      initialTo: wdaysAgo(0),
      filters: [
        WaterFilterDef(
          key: 'customer',
          label: '',
          initial: 'ALL',
          summaryLabel: 'Customer',
          options: (q) async => [
            ('ALL', 'Pick customer…'),
            for (final c in await q.list('/api/Water/customers')) ('${c['waterCustomerId']}', '${c['name'] ?? ''}'),
          ],
        ),
      ],
      load: (q) async {
        final id = q.filters['customer'];
        final customers = await q.listOrEmpty('/api/Water/customers');
        final name = customers.where((c) => '${c['waterCustomerId']}' == id).firstOrNull?['name'];
        if (id == null || id == 'ALL') return {'sales': <Map<String, dynamic>>[], 'name': null};
        final all = await q.list('/api/Water/sales');
        final inScope = [
          for (final s in all)
            if ('${s['waterCustomerId']}' == id &&
                wday(s['saleDate']).compareTo(q.from) >= 0 &&
                wday(s['saleDate']).compareTo(q.to) <= 0)
              s,
        ];
        final sales = <Map<String, dynamic>>[];
        for (final s in inScope) {
          final payments = await q.listOrEmpty('/api/Water/payments/by-sale/${s['waterSaleId']}');
          sales.add({
            'saleId': s['waterSaleId'],
            'date': wday(s['saleDate']),
            'total': wn(s['totalAmount']),
            'paid': wn(s['amountPaid']),
            'balance': wn(s['totalAmount']) - wn(s['amountPaid']),
            'status': s['status'] ?? '—',
            'payments': [
              for (final p in payments) (wday(p['paymentDate']), wn(p['amount']), '${p['paymentMethod'] ?? '—'}'),
            ],
          });
        }
        sales.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
        return {'sales': sales, 'name': name};
      },
      view: (data, q, m) {
        final d = data as Map? ?? const {};
        final sales = (d['sales'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        final name = d['name'] as String?;
        final picked = q.filters['customer'] != 'ALL';
        final revenue = sales.fold<num>(0, (t, r) => t + wn(r['total']));
        final paid = sales.fold<num>(0, (t, r) => t + wn(r['paid']));
        final balance = sales.fold<num>(0, (t, r) => t + wn(r['balance']));
        final columns = [col('Sale date'), col('Sale #'), rcol('Total'), rcol('Paid'), rcol('Balance'), col('Status'), col('Payments')];
        final rows = [
          for (final r in sales)
            [
              '${r['date']}',
              wstr(r['saleId']),
              m(wn(r['total'])),
              m(wn(r['paid'])),
              m(wn(r['balance'])),
              '${r['status']}',
              (r['payments'] as List).isEmpty
                  ? '—'
                  : [for (final (String pd, num a, String meth) in (r['payments'] as List).cast<(String, num, String)>()) '$pd · $meth · ${m(a)}']
                      .join('; '),
            ],
        ];
        return WaterReportView(
          tiles: picked
              ? [
                  tile('Sales count', '${sales.length}'),
                  tile('Revenue', m(revenue)),
                  tile('Paid', m(paid), 'green'),
                  tile('Balance', m(balance), balance > 0 ? 'rose' : 'green'),
                ]
              : const [],
          columns: columns,
          rows: rows,
          subtitle: name == null ? null : 'Customer: $name',
          activeFilters: [if (name != null && name.trim().isNotEmpty) ('Customer', name)],
          before: picked
              ? [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text.rich(TextSpan(style: const TextStyle(fontSize: 13, color: slate600), children: [
                      const TextSpan(text: 'Customer: '),
                      TextSpan(text: name ?? '—', style: const TextStyle(fontWeight: FontWeight.w500)),
                    ])),
                  ),
                ]
              : const [
                  Text('Pick a customer above to load their history.', style: TextStyle(fontSize: 13, color: slate500)),
                ],
          sections: picked
              ? [WaterSection(columns: columns, rows: rows, empty: 'No sales for this customer in the selected period.')]
              : const [],
        );
      },
    );

// ----------------------------------------------------------- Top Customers

Widget waterTopCustomersReport(Session s, Company c) => WaterReport(
      session: s,
      company: c,
      slug: 'top-customers',
      title: 'Top Customers',
      description: 'Highest-value customers by total sales for the period.',
      filename: 'water-top-customers',
      filters: [
        WaterFilterDef(
          key: 'topN',
          label: 'Show',
          initial: '10',
          summaryLabel: 'Top N',
          options: (_) async => [for (final n in [5, 10, 20, 50]) ('$n', 'Top $n')],
        ),
      ],
      load: (q) => q.list('/api/Water/reports/top-customers', {...q.period, 'topN': q.filters['topN']}),
      view: (data, q, m) {
        final rows = data as List<Map<String, dynamic>>? ?? const [];
        final topN = q.filters['topN'] ?? '10';
        return WaterReportView(
          tiles: [
            tile('Customers', '${rows.length}'),
            tile('Total sales', m(rows.fold<num>(0, (t, r) => t + wn(r['totalSales']))), 'green'),
            tile('Total paid', m(rows.fold<num>(0, (t, r) => t + wn(r['totalPaid']))), 'green'),
            tile('Outstanding', m(rows.fold<num>(0, (t, r) => t + wn(r['outstandingBalance']))), 'rose'),
          ],
          columns: [col('Customer'), col('Phone'), rcol('Sales'), rcol('Total sales'), rcol('Paid'), rcol('Outstanding')],
          rows: [
            for (final r in rows)
              [
                '${r['customerName'] ?? ''}',
                wdash(r['phoneNumber']),
                wloc(r['salesCount']),
                m(wn(r['totalSales'])),
                m(wn(r['totalPaid'])),
                m(wn(r['outstandingBalance'])),
              ],
          ],
          empty: 'No customer sales in this period.',
          subtitle: 'Top $topN',
          activeFilters: [('Top N', topN)],
        );
      },
    );
