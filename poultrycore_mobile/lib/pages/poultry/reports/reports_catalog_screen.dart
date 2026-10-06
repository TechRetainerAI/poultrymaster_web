import 'package:flutter/material.dart';

import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import 'report_routes.dart';
import 'report_widgets.dart';

typedef ReportMenuItem = ({String id, String title, String description, IconData icon, String href});
typedef ReportMenuGroup = ({
  String key,
  String label,
  String blurb,
  Color color,
  Color tintBg,
  Color tintFg,
  List<ReportMenuItem> items,
});

/// POULTRY_REPORT_MENU_GROUPS (`lib/reports/poultry-reports-config.ts`): four
/// sections, 29 reports, in the web's order.
const List<ReportMenuGroup> poultryReportMenuGroups = [
  (
    key: 'money',
    label: 'Sales, Money & Profit',
    blurb: "Money in, money out, what's left",
    color: Color(0xFF15803D),
    tintBg: Color(0xFFF0FDF4),
    tintFg: Color(0xFF15803D),
    items: [
      (id: 'profit-loss', title: 'Profit & Loss (Company)', description: 'Company-wide revenue, expenses and net profit.', icon: Icons.balance, href: '/poultry/reports/profit-loss'),
      (id: 'daily-business-summary', title: 'Daily Business Summary', description: 'Full daily snapshot — income, production, purchases, expenses, losses, cash.', icon: Icons.bar_chart, href: '/poultry-daily-summary'),
      (id: 'closing-report', title: 'Closing Report', description: 'Every daily closing, with cash reconciliation and approval status.', icon: Icons.assignment_outlined, href: '/poultry-closing-report-daily'),
      (id: 'closing-by-category', title: 'Closing by Category', description: 'Period totals grouped into financial, production, inventory and birds.', icon: Icons.fact_check_outlined, href: '/poultry-closing-report'),
      (id: 'profit-loss-by-flock', title: 'Profit & Loss by Flock', description: 'Revenue, expenses and profit per flock.', icon: Icons.trending_up, href: '/poultry/reports/profit-loss-by-flock'),
      (id: 'egg-sales', title: 'Egg Sales', description: 'Sales by date, customer and product.', icon: Icons.monetization_on_outlined, href: '/poultry/reports/egg-sales'),
      (id: 'customer-balance', title: 'Customer Balance', description: 'Customer receivables.', icon: Icons.people_outline, href: '/poultry/reports/customer-balance'),
      (id: 'supplier-balance', title: 'Supplier Balance', description: 'Supplier payables.', icon: Icons.local_shipping_outlined, href: '/poultry/reports/supplier-balance'),
      (id: 'expense-summary', title: 'Expense Summary', description: 'Farm expenses by category and flock.', icon: Icons.receipt_long_outlined, href: '/poultry/reports/expense-summary'),
      (id: 'cash-movement', title: 'Cash Movement', description: 'Cash inflows and outflows.', icon: Icons.account_balance_wallet_outlined, href: '/poultry/reports/cash-movement'),
      (id: 'cash-flow-detail', title: 'Cash Flow Detail', description: 'Where cash came from and what it went on, with analysis.', icon: Icons.pie_chart_outline, href: '/poultry/reports/cash-flow-detail'),
      (id: 'cash-accounts', title: 'Cash Account Report', description: 'Per-account opening, in, out and closing, with drift and reconciliation status.', icon: Icons.account_balance_outlined, href: '/poultry/reports/cash-accounts'),
      (id: 'money-movement', title: 'Money Movement', description: 'Cash transfers, owner contributions and draws, loans and repayments — none of it revenue or expense, except loan interest and fees.', icon: Icons.account_balance_wallet_outlined, href: '/poultry/reports/money'),
      (id: 'cost-per-egg', title: 'Cost Per Egg', description: 'Total allocated cost per egg.', icon: Icons.calculate_outlined, href: '/poultry/reports/cost-per-egg'),
    ],
  ),
  (
    key: 'production',
    label: 'Production & Eggs',
    blurb: "What the birds laid, and what's in store",
    color: Color(0xFF059669),
    tintBg: Color(0xFFECFDF5),
    tintFg: Color(0xFF047857),
    items: [
      (id: 'daily-egg-production', title: 'Daily Egg Production', description: 'Eggs by day and flock, with collection times.', icon: Icons.egg_outlined, href: '/poultry/reports/daily-egg-production'),
      (id: 'flock-production-summary', title: 'Flock Production Summary', description: 'Compare production performance across flocks.', icon: Icons.bar_chart, href: '/poultry/reports/flock-production-summary'),
      (id: 'hen-day-production', title: 'Hen-Day Production', description: 'Production relative to live birds.', icon: Icons.show_chart, href: '/poultry/reports/hen-day-production'),
      (id: 'batch-production-summary', title: 'Batch Production Summary', description: 'Production performance rolled up per flock batch.', icon: Icons.inventory_2_outlined, href: '/poultry/reports/batch-production-summary'),
      (id: 'egg-stock-balance', title: 'Egg Stock Balance', description: 'Egg inventory on hand, in eggs and crates.', icon: Icons.inventory_2_outlined, href: '/poultry/reports/egg-stock-balance'),
      (id: 'missing-daily-records', title: 'Missing Daily Records', description: 'Active flocks missing required daily records.', icon: Icons.fact_check_outlined, href: '/poultry/reports/missing-daily-records'),
    ],
  ),
  (
    key: 'feed-birds-health',
    label: 'Feed, Birds & Health',
    blurb: 'Feed, head count, losses, vaccines and medicine',
    color: Color(0xFFCA8A04),
    tintBg: Color(0xFFFEFCE8),
    tintFg: Color(0xFFA16207),
    items: [
      (id: 'feed-usage', title: 'Feed Usage', description: 'Feed consumed by flock, date and type.', icon: Icons.grass, href: '/poultry/reports/feed-usage'),
      (id: 'feed-inventory-balance', title: 'Feed Inventory Balance', description: 'Current feed stock and days remaining.', icon: Icons.inventory_outlined, href: '/poultry/reports/feed-inventory-balance'),
      (id: 'feed-cost-per-egg', title: 'Feed Cost Per Egg', description: 'How feed cost relates to egg production.', icon: Icons.calculate_outlined, href: '/poultry/reports/feed-cost-per-egg'),
      (id: 'feed-production-report', title: 'Feed Production', description: 'Feed produced and ingredient usage, with full costing.', icon: Icons.factory_outlined, href: '/poultry-feed-production/reports'),
      (id: 'mortality', title: 'Mortality', description: 'Deaths and mortality percentages.', icon: Icons.heart_broken_outlined, href: '/poultry/reports/mortality'),
      (id: 'birds-on-hand', title: 'Birds on Hand', description: 'Current bird count and reconciliation.', icon: Icons.flutter_dash, href: '/poultry/reports/birds-on-hand'),
      (id: 'end-of-flock', title: 'End-of-Flock', description: 'Final lifecycle performance per flock.', icon: Icons.flag_outlined, href: '/poultry/reports/end-of-flock'),
      (id: 'vaccination-schedule', title: 'Vaccination Schedule', description: 'Recorded and upcoming vaccinations.', icon: Icons.vaccines_outlined, href: '/poultry/reports/vaccination-schedule'),
      (id: 'medicine-usage', title: 'Medicine Usage', description: 'Medicines used by flock and date.', icon: Icons.medication_outlined, href: '/poultry/reports/medicine-usage'),
    ],
  ),
  (
    key: 'overview',
    label: 'Overview & Dashboards',
    blurb: 'The whole farm at a glance',
    color: Color(0xFF2563EB),
    tintBg: Color(0xFFEFF6FF),
    tintFg: Color(0xFF1D4ED8),
    items: [
      (id: 'farm-summary', title: 'Poultry Farm Summary', description: 'High-level snapshot of the whole farm for the period.', icon: Icons.dashboard_outlined, href: '/poultry/reports/farm-summary'),
      (id: 'production-dashboard', title: 'Production Dashboard', description: 'Egg production trends, collection times and flock metrics.', icon: Icons.egg_outlined, href: '/poultry/reports/production'),
      (id: 'financial-dashboard', title: 'Financial Dashboard', description: 'Revenue, expenses and net profit / loss.', icon: Icons.account_balance_wallet_outlined, href: '/poultry/reports/financial'),
      (id: 'daily', title: 'Daily Report', description: 'Daily eggs vs expenses, best and worst days.', icon: Icons.calendar_month_outlined, href: '/poultry/reports/daily'),
      (id: 'more', title: 'More Reports', description: 'Sales by product, expense categories and flock performance.', icon: Icons.trending_up, href: '/poultry/reports/more'),
      (id: 'changes', title: 'Changes Report', description: 'Every create, update and delete of records — who changed what, and when.', icon: Icons.history, href: '/poultry/reports/changes'),
    ],
  ),
];

/// /poultry/reports — every Poultry report, one card per section.
class PoultryReportsCatalogScreen extends StatelessWidget {
  const PoultryReportsCatalogScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, session, company, href: '/poultry/reports');
    final total = poultryReportMenuGroups.fold(0, (n, g) => n + g.items.length);
    return Scaffold(
      backgroundColor: slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFDBEAFE), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.bar_chart, color: Color(0xFF1D4ED8)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$total reports in ${poultryReportMenuGroups.length} sections — each with its own filters, summary cards and PDF export.',
                style: const TextStyle(fontSize: 13, color: slate500),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          for (final g in poultryReportMenuGroups) ...[
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: slate200),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: slate100))),
                  child: Row(children: [
                    Container(width: 4, height: 28, decoration: BoxDecoration(color: g.color, borderRadius: BorderRadius.circular(99))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(g.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: slate900)),
                        Text(g.blurb, style: const TextStyle(fontSize: 11.5, color: slate500)),
                      ]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: slate100, borderRadius: BorderRadius.circular(99)),
                      child: Text('${g.items.length}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: slate600)),
                    ),
                  ]),
                ),
                for (final r in g.items)
                  InkWell(
                    onTap: () => openReportHref(context, session, company, r.href, label: r.title),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      child: Row(children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(color: g.tintBg, borderRadius: BorderRadius.circular(8)),
                          child: Icon(r.icon, size: 18, color: g.tintFg),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(r.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: slate900)),
                            Text(r.description,
                                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: slate500)),
                          ]),
                        ),
                        const Icon(Icons.chevron_right, size: 18, color: slate300),
                      ]),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}
