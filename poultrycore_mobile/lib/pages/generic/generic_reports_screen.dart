// Generic → Admin → Reports, as `app/generic-reports/page.tsx`: the reports
// hub. Subscription reports only for a business that bills on a schedule,
// Money for everyone, Products & stock unless Products is switched off. The
// card titles use the company's own words (Members, Fee Bills…).

import 'package:flutter/material.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/trackers/tracker_widgets.dart';
import '../web_nav.dart' show NavLink;
import 'generic_kit.dart';

/// One report card: where it goes, what it says, its icon and accent.
class GenericReportCard {
  const GenericReportCard(this.href, this.title, this.description, this.icon, this.accent);
  final String href, title, description;
  final IconData icon;
  final (Color fg, Color bg) accent;
}

const _emerald = (Color(0xFF059669), Color(0xFFECFDF5));
const _sky = (Color(0xFF0284C7), Color(0xFFF0F9FF));
const _cyan = (Color(0xFF0891B2), Color(0xFFECFEFF));
const _amber = (Color(0xFFD97706), Color(0xFFFFFBEB));
const _orange = (Color(0xFFEA580C), Color(0xFFFFF7ED));
const _slate = (Color(0xFF475569), Color(0xFFF1F5F9));
const _rose = (Color(0xFFE11D48), Color(0xFFFFF1F2));
const _violet = (Color(0xFF7C3AED), Color(0xFFF5F3FF));

/// coreReports: every Generic company gets these.
List<GenericReportCard> genericCoreReports(GenericLabels l) => [
      const GenericReportCard('/generic-reports/period-pnl', 'Profit & loss',
          'Income, expenses, cost-of-goods-sold and profit for any date range.', Icons.attach_money, _emerald),
      const GenericReportCard('/generic-reports/cash-summary', 'Cash flow',
          'Money in, money out and the closing balance of every cash account.', Icons.account_balance_wallet_outlined, _slate),
      const GenericReportCard('/generic-reports/expenses-by-category', 'Expense report',
          'Where the money went — by category, by supplier, and month by month.', Icons.bar_chart, _amber),
      GenericReportCard('/generic-customer-balances', '${l.customerBalance} report',
          'Who owes what, how old it is, and every open ${l.invoice.toLowerCase()} behind it.', Icons.balance_outlined, _cyan),
      const GenericReportCard('/generic-supplier-balances', 'Supplier balances',
          'What is owed to suppliers, aged, with the bills behind each balance.', Icons.local_shipping_outlined, _orange),
      const GenericReportCard('/generic-reports/staff-cost', 'Staff & contractor cost',
          'Everything paid to people — staff payments and payroll — by person, month and role.', Icons.groups_2_outlined, _violet),
    ];

/// subscriptionReports: only for a business that bills on a schedule.
List<GenericReportCard> genericSubscriptionReports(GenericLabels l) => [
      GenericReportCard('/generic-reports/subscription-revenue', '${l.subscription} revenue',
          'What was billed and collected, split by month, by ${l.plan.toLowerCase()} and by ${l.customer.toLowerCase()}.',
          Icons.repeat, _emerald),
      const GenericReportCard('/generic-reports/mrr', 'Monthly recurring revenue',
          'Active, new and lost MRR month by month.', Icons.trending_up, _sky),
      GenericReportCard('/generic-reports/customer-payments', '${l.customer} payments',
          'Every payment received, how it was paid, and what it settled.', Icons.credit_card, _cyan),
      GenericReportCard('/generic-reports/unpaid-customers', 'Unpaid ${l.customerPlural.toLowerCase()}',
          'Who is late, by how much, for how long, and how to reach them.', Icons.warning_amber_outlined, _rose),
      const GenericReportCard('/generic-reports/hosting-cost', 'Hosting & cloud cost',
          'What infrastructure costs each month, and what share of revenue it eats.', Icons.cloud_outlined, _violet),
      GenericReportCard('/generic-reports/break-even', 'Break-even',
          'How many paying ${l.customerPlural.toLowerCase()} it takes to cover a month.', Icons.balance_outlined, _amber),
    ];

/// retailReports: only meaningful when the company sells things.
const genericRetailReports = [
  GenericReportCard('/generic-reports/sales-by-product', 'Sales by product',
      'Which products generated the most revenue this period.', Icons.shopping_cart_outlined, _sky),
  GenericReportCard('/generic-reports/sales-by-customer', 'Sales by customer',
      'Top customers by revenue, including outstanding balances.', Icons.people_outline, _cyan),
  GenericReportCard('/generic-reports/inventory-value', 'Inventory value',
      'Stock value at cost and at retail, with a per-category breakdown.', Icons.inventory_2_outlined, _orange),
];

class GenericReportsScreen extends StatefulWidget {
  const GenericReportsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<GenericReportsScreen> createState() => _GenericReportsScreenState();
}

class _GenericReportsScreenState extends State<GenericReportsScreen> {
  GenericModules _gm = const GenericModules();

  @override
  void initState() {
    super.initState();
    loadGenericModules(widget.session, widget.company).then((v) {
      if (mounted) setState(() => _gm = v);
    });
  }

  void _open(GenericReportCard r) =>
      openNavLink(Navigator.of(context), NavLink(r.title, r.href, null), widget.session, widget.company);

  Widget _section(String title, List<GenericReportCard> cards) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          genericEyebrow(title),
          for (final r in cards)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: TColors.slate200),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _open(r),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: r.accent.$2, borderRadius: BorderRadius.circular(6)),
                          child: Icon(r.icon, size: 20, color: r.accent.$1),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.title,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: TColors.slate900)),
                              const SizedBox(height: 4),
                              Text(r.description, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final l = _gm.labels;
    // A company with no settings row keeps the stock reports.
    final showRetail = _gm.settings == null ? true : _gm.settings!['enableProducts'] == true;
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/generic-reports');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          const GenericTitle(
            icon: Icons.bar_chart,
            title: 'Reports',
            subtitle: 'Aggregations over the immutable sales / purchases / expenses / cash / ledger tables.',
          ),
          const SizedBox(height: 12),
          if (_gm.isSubscriptionBusiness) _section('${l.subscription} reports', genericSubscriptionReports(l)),
          _section('Money', genericCoreReports(l)),
          if (showRetail) _section('Products & stock', genericRetailReports),
        ],
      ),
    );
  }
}
