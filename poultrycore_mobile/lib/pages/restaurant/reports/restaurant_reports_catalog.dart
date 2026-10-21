// lib/reports/restaurant-reports-config.ts and app/restaurant-reports/page.tsx:
// the 34 Restaurant reports in six groups, each with the date control it
// needs, and the catalog page that lists them.

import 'package:flutter/material.dart';

import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../poultry/trackers/tracker_widgets.dart' show TColors;
import 'restaurant_report_routes.dart';

class RestaurantReportEntry {
  const RestaurantReportEntry(this.slug, this.title, this.description, this.icon, {this.dateMode = 'range', this.isNew = false});
  final String slug;
  final String title;
  final String description;
  final IconData icon;

  /// range (From / To with presets), single (one day with a stepper) or none.
  final String dateMode;

  /// Shown on the catalog card.
  final bool isNew;
}

class RestaurantReportGroup {
  const RestaurantReportGroup(this.key, this.label, this.color, this.reports);
  final String key;
  final String label;

  /// The group's chip colour (bg-*-600).
  final Color color;
  final List<RestaurantReportEntry> reports;
}

const restaurantReportGroups = [
  RestaurantReportGroup('money', 'Money', Color(0xFF059669), [
    RestaurantReportEntry('pnl', 'Profit & Loss', 'Revenue, cost of goods, expenses and net profit for the period',
        Icons.account_balance_wallet_outlined, isNew: true),
    RestaurantReportEntry('sales-summary', 'Sales Summary', 'Every headline sales number for a date range, in one place', Icons.attach_money,
        isNew: true),
    RestaurantReportEntry('payment-methods', 'Payment Methods', 'Cash, card and mobile money split, with tips and share of take',
        Icons.toll_outlined, isNew: true),
    RestaurantReportEntry('expenses', 'Expenses', 'Spend by category, supplier and payment method', Icons.receipt_long_outlined, isNew: true),
    RestaurantReportEntry('discounts', 'Discounts & Promotions', 'What each discount was actually given away, and on what', Icons.percent,
        isNew: true),
    RestaurantReportEntry('profit-vs-cash', 'Profit vs Cash', 'Why the cash moved differently from the profit, line by line', Icons.balance,
        isNew: true),
    RestaurantReportEntry('payroll', 'Payroll',
        'Wages paid per staff member: gross, deductions, staff loan repayments and net pay', Icons.payments_outlined, isNew: true),
    RestaurantReportEntry('staff-loans', 'Employee Loans & Advances', 'What each staff member owes, and what was advanced and repaid in the period',
        Icons.volunteer_activism_outlined, isNew: true),
  ]),
  // 323 / 324: every report here reads the one cash ledger.
  RestaurantReportGroup('cash', 'Cash & Ledger', Color(0xFF0284C7), [
    RestaurantReportEntry('cash-flow-detail', 'Cash Flow Detail', 'Every movement with running cash, daily chart, breakdowns and analysis',
        Icons.monitor_heart_outlined, isNew: true),
    RestaurantReportEntry('cash-movement', 'Cash Movement', 'Money in, out and cash held at the end of each day', Icons.swap_vert, isNew: true),
    RestaurantReportEntry('cash-accounts', 'Cash Account Report',
        "Where the money sits: each account's opening, in, out and closing, plus the ledger", Icons.account_balance_outlined, isNew: true),
    RestaurantReportEntry('money-movement', 'Money Movement', 'Transfers, owner contributions and drawings, loans and repayments',
        Icons.compare_arrows, isNew: true),
    RestaurantReportEntry('takings-by-account', 'Takings by Account', "Which till, bank or wallet each payment method's money landed in",
        Icons.account_balance_wallet_outlined, isNew: true),
    RestaurantReportEntry('till-variances', 'Till & Count Variances', 'Every shift cash-up and account count, with over and short',
        Icons.calculate_outlined, isNew: true),
    RestaurantReportEntry('closing-report', 'Closing Report', 'One row per closed day: sales, money in and out, over / short',
        Icons.event_available_outlined, isNew: true),
  ]),
  RestaurantReportGroup('sales', 'Sales', Color(0xFFE11D48), [
    RestaurantReportEntry('daily-sales', 'Daily Sales', 'One day in full — revenue, order types and payment split', Icons.attach_money,
        dateMode: 'single'),
    RestaurantReportEntry('revenue-trend', 'Revenue Trend', 'Daily revenue and order count across the period', Icons.trending_up),
    RestaurantReportEntry('top-items', 'Top Selling Items', 'Best sellers by revenue, quantity and order count', Icons.restaurant_menu),
    RestaurantReportEntry('sales-by-category', 'Sales by Category', 'Revenue and quantity sold per menu category', Icons.pie_chart_outline),
    RestaurantReportEntry('peak-hours', 'Peak Hours', 'Busiest hours of a day by orders and revenue', Icons.schedule, dateMode: 'single'),
  ]),
  RestaurantReportGroup('menu', 'Menu & Food', Color(0xFFD97706), [
    RestaurantReportEntry('menu-engineering', 'Menu Engineering', 'Popularity against margin — Stars, Plowhorses, Puzzles and Dogs',
        Icons.soup_kitchen_outlined, isNew: true),
    RestaurantReportEntry('food-cost', 'Food Cost', 'Recipe cost against selling price, margin and food cost percent', Icons.restaurant,
        dateMode: 'none'),
    RestaurantReportEntry('waste', 'Waste', 'What was thrown away, why, and what it cost', Icons.delete_outline, isNew: true),
  ]),
  RestaurantReportGroup('operations', 'Operations', Color(0xFF2563EB), [
    RestaurantReportEntry('kitchen-performance', 'Kitchen Performance', 'Queue and cook times per station, and the slowest item on each',
        Icons.timer_outlined, isNew: true),
    RestaurantReportEntry('table-turnover', 'Table Turnover', 'Dwell time, turns per day and revenue per cover, per table',
        Icons.table_restaurant_outlined, isNew: true),
    RestaurantReportEntry('waiter-performance', 'Waiter Performance', 'Orders, covers, revenue and average ticket per waiter',
        Icons.groups_outlined),
    RestaurantReportEntry('tips', 'Tips', 'Tips per waiter as an amount and as a percentage of their sales', Icons.toll_outlined, isNew: true),
    RestaurantReportEntry('voids', 'Voids & Cancellations', 'Cancelled and refunded orders grouped by the reason given', Icons.block,
        isNew: true),
    RestaurantReportEntry('stock-on-hand', 'Stock on Hand', 'Current stock against par and reorder levels, worst first',
        Icons.inventory_2_outlined, dateMode: 'none', isNew: true),
  ]),
  RestaurantReportGroup('guests', 'Guests & Channels', Color(0xFF7C3AED), [
    RestaurantReportEntry('customer-retention', 'Customer Retention', 'New against returning guests, repeat rate, visits and spend',
        Icons.favorite_border, isNew: true),
    RestaurantReportEntry('feedback', 'Guest Feedback', 'Ratings by source, including QR guest ratings', Icons.star_border, isNew: true),
    RestaurantReportEntry('delivery-performance', 'Delivery Performance', 'Promised against actual delivery times, per driver',
        Icons.local_shipping_outlined, isNew: true),
    RestaurantReportEntry('channel', 'Channel Profitability', 'What each delivery platform keeps in commission and fees',
        Icons.storefront_outlined, isNew: true),
    RestaurantReportEntry('events', 'Events & Catering', 'Booked value, deposits taken and balances still owed', Icons.calendar_month_outlined,
        isNew: true),
  ]),
];

final allRestaurantReports = [for (final g in restaurantReportGroups) ...g.reports];

({RestaurantReportEntry report, RestaurantReportGroup group})? findRestaurantReport(String slug) {
  for (final g in restaurantReportGroups) {
    for (final r in g.reports) {
      if (r.slug == slug) return (report: r, group: g);
    }
  }
  return null;
}

/// Slugs the old catalog used, mapped to where that report lives now.
const restaurantLegacySlugs = {
  'overview': 'sales-summary',
  'daily': 'daily-sales',
  'trends': 'revenue-trend',
  'income': 'pnl',
  'items': 'top-items',
  'foodcost': 'food-cost',
  'categories': 'sales-by-category',
  'hours': 'peak-hours',
  'servers': 'waiter-performance',
  'orders': 'sales-summary',
  'daily-report': 'daily-sales',
  'weekly-report': 'revenue-trend',
  'monthly-report': 'revenue-trend',
};

void openRestaurantReportsCatalog(BuildContext context, Session session, Company company) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RestaurantReportsCatalogScreen(session: session, company: company)),
    );

class RestaurantReportsCatalogScreen extends StatelessWidget {
  const RestaurantReportsCatalogScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, session, company, href: '/restaurant-reports');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Reports')),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 32), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFFE4E6), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.bar_chart, size: 22, color: Color(0xFFBE123C)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Reports', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900)),
              const SizedBox(height: 2),
              Text(
                '${allRestaurantReports.length} reports. Every one takes a date range, previews as a PDF before you download it, and exports to CSV.',
                style: const TextStyle(fontSize: 13, color: TColors.slate500),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        for (final g in restaurantReportGroups) ...[
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                color: g.color,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(g.label.toUpperCase(),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: .6, color: Colors.white)),
              ),
              for (final (i, r) in g.reports.indexed)
                InkWell(
                  onTap: () => openRestaurantReport(context, session, company, r.slug),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(border: i < g.reports.length - 1 ? const Border(bottom: BorderSide(color: TColors.slate200)) : null),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(r.icon, size: 16, color: TColors.slate400),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            Text(r.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate900)),
                            if (r.isNew)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(color: const Color(0xFFFFE4E6), borderRadius: BorderRadius.circular(999)),
                                child: const Text('New', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFBE123C))),
                              ),
                          ]),
                          const SizedBox(height: 2),
                          Text(r.description, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                        ]),
                      ),
                      // Always visible: a hover-only chevron cannot be reached on touch.
                      const Icon(Icons.chevron_right, size: 16, color: Color(0xFFCBD5E1)),
                    ]),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 14),
        ],
        const Wrap(spacing: 16, runSpacing: 6, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.visibility_outlined, size: 14, color: TColors.slate500),
            SizedBox(width: 6),
            Flexible(child: Text('View the PDF before downloading', style: TextStyle(fontSize: 12, color: TColors.slate500))),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.table_view_outlined, size: 14, color: TColors.slate500),
            SizedBox(width: 6),
            Flexible(child: Text('CSV export on every report', style: TextStyle(fontSize: 12, color: TColors.slate500))),
          ]),
        ]),
      ]),
    );
  }
}
