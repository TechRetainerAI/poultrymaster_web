import 'package:flutter/material.dart';

import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../poultry/reports/report_widgets.dart';
import 'water_report_routes.dart';

typedef WaterReportItem = ({String slug, String title, String description, IconData icon});
typedef WaterReportGroup = ({String key, String label, Color color, List<WaterReportItem> reports});

/// WATER_REPORT_GROUPS (`lib/reports/water-reports-config.ts`): the single
/// source for the Reports index and the top-nav Reports menu — four groups,
/// 27 reports, in the web's order.
const List<WaterReportGroup> waterReportGroups = [
  (
    key: 'financial',
    label: 'Financial',
    color: Color(0xFF059669), // emerald-600
    reports: [
      (slug: 'closing-report', title: 'Closing Report', description: 'Daily closings (including reopened + superseded).', icon: Icons.description_outlined),
      (slug: 'profit-loss', title: 'Profit & Loss', description: 'Revenue, costs, expenses, losses, gross & net profit by period.', icon: Icons.trending_down),
      (slug: 'daily-summary', title: 'Daily Business Summary', description: 'Full daily snapshot — sales, payments, expenses, production, losses, cash.', icon: Icons.bar_chart),
      (slug: 'cash-movement', title: 'Cash Movement', description: 'Every cash inflow and outflow, with a running balance.', icon: Icons.account_balance_wallet_outlined),
      (slug: 'cash-flow-detail', title: 'Cash Flow Detail', description: 'Where cash came from and what it went on, with analysis.', icon: Icons.pie_chart_outline),
      (slug: 'cash-accounts', title: 'Cash Account Report', description: 'Per-account opening, in, out and closing, with drift and reconciliation status.', icon: Icons.account_balance_outlined),
      (slug: 'money-movement', title: 'Money Movement', description: 'Cash transfers, owner contributions and draws, loans and repayments — none of it revenue or expense, except loan interest and fees.', icon: Icons.swap_horiz),
      (slug: 'expense-report', title: 'Expense Report', description: 'Expenses grouped by category, source, payment method.', icon: Icons.receipt_long_outlined),
      (slug: 'supplier-activity', title: 'Supplier Activity', description: 'Per-supplier purchases, expenses paid, outstanding balance, last activity.', icon: Icons.receipt_long_outlined),
    ],
  ),
  (
    key: 'sales-customers',
    label: 'Sales & Customers',
    color: Color(0xFF0284C7), // sky-600
    reports: [
      (slug: 'sales-report', title: 'Sales Report', description: 'All sales — date, customer, products, status, source.', icon: Icons.shopping_cart_outlined),
      (slug: 'payments-received', title: 'Payments Received', description: 'Collections by date, customer, method, source.', icon: Icons.attach_money),
      (slug: 'customer-balances', title: 'Customer Balances', description: 'Receivables with aging.', icon: Icons.savings_outlined),
      (slug: 'customer-history', title: 'Customer Sales History', description: 'Per-customer sales + payment timeline.', icon: Icons.history),
      (slug: 'top-customers', title: 'Top Customers', description: 'Highest-value customers by total sales for the period.', icon: Icons.people_outline),
    ],
  ),
  (
    key: 'production-inventory',
    label: 'Production & Inventory',
    color: Color(0xFF4F46E5), // indigo-600
    reports: [
      (slug: 'production-report', title: 'Production Report', description: 'Production records, machine, product, good bags, cost/bag, efficiency.', icon: Icons.factory_outlined),
      (slug: 'raw-material-usage', title: 'Raw Material Usage', description: 'Expected vs actual usage with variance.', icon: Icons.layers_outlined),
      (slug: 'raw-material-purchase', title: 'Raw Material Purchases', description: 'Suppliers, costs, payment methods.', icon: Icons.shopping_bag_outlined),
      (slug: 'inventory-report', title: 'Inventory / Stock', description: 'Current stock by product/material with low-stock alerts.', icon: Icons.inventory_2_outlined),
      (slug: 'stock-movement', title: 'Stock Movement', description: 'All inventory movements — type, direction, source.', icon: Icons.speed),
      (slug: 'product-performance', title: 'Product Performance', description: 'Per-product sales, cost, gross profit estimate.', icon: Icons.shopping_bag_outlined),
    ],
  ),
  (
    key: 'delivery-operations',
    label: 'Delivery & Operations',
    color: Color(0xFFE11D48), // rose-600
    reports: [
      (slug: 'delivery-run-report', title: 'Delivery Run Report', description: 'Loadings, returns, shortages, status.', icon: Icons.local_shipping_outlined),
      (slug: 'driver-accountability', title: 'Driver Accountability', description: 'Per-driver loadings, sales, returns, damages, shortages.', icon: Icons.people_outline),
      (slug: 'route-performance', title: 'Route Performance', description: 'Per-route sales, collections, customers served.', icon: Icons.alt_route),
      (slug: 'driver-collection', title: 'Driver Collection', description: 'Per-driver cash/MoMo/bank collections, credit, shortages, per-product detail.', icon: Icons.account_balance_wallet_outlined),
      (slug: 'vehicle-usage', title: 'Vehicle Usage', description: 'Per-vehicle runs, sales, expenses.', icon: Icons.local_shipping_outlined),
      (slug: 'loss-report', title: 'Loss Report', description: 'Damages, rejected, manual + delivery losses by source.', icon: Icons.trending_down),
      (slug: 'operational', title: 'Operational dashboard', description: 'Route profitability, driver reconciliation, raw material variance.', icon: Icons.bar_chart),
    ],
  ),
];

/// /water-reports — the index: one section per group, one row per report.
class WaterReportsCatalogScreen extends StatelessWidget {
  const WaterReportsCatalogScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, session, company, href: '/water-reports');
    final total = waterReportGroups.fold(0, (n, g) => n + g.reports.length);
    return Scaffold(
      backgroundColor: slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.bar_chart, color: Color(0xFF0369A1)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Reports', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: slate900)),
                const SizedBox(height: 2),
                Text('$total reports — each with its own filters, summary cards and PDF export.',
                    style: const TextStyle(fontSize: 13, color: slate500)),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          for (final g in waterReportGroups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: g.color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(g.label.toUpperCase(),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .8, color: slate500)),
                const SizedBox(width: 6),
                Text('${g.reports.length}', style: const TextStyle(fontSize: 11, color: slate400)),
              ]),
            ),
            for (final r in g.reports)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: slate200),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => openWaterReport(context, session, company, r.slug, label: r.title),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(color: g.color, borderRadius: BorderRadius.circular(6)),
                          child: Icon(r.icon, size: 16, color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(r.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: slate900)),
                            Text(r.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, color: slate500)),
                          ]),
                        ),
                        // The web's chevron only fades in on hover, so a phone
                        // never shows it.
                      ]),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
