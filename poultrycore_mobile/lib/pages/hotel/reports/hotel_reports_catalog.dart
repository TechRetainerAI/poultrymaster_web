// lib/reports/hotel-reports-config.ts and app/hotel-reports/page.tsx: the 27
// Hotel reports in six groups, and the catalog page that lists them. Each row
// opens /hotel-reports/<slug>.

import 'package:flutter/material.dart';

import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../poultry/reports/report_routes.dart' show openAppHref;
import '../../poultry/trackers/tracker_widgets.dart' show TColors;
import '../../restaurant/reports/restaurant_reports_catalog.dart' show RestaurantReportEntry, RestaurantReportGroup;
import 'hotel_report_routes.dart';

typedef E = RestaurantReportEntry;

/// HOTEL_REPORT_GROUPS. The 17 original reports own their pages and filters;
/// the ones marked new go through the shared report shell with the dateMode
/// given here.
const hotelReportGroups = [
  RestaurantReportGroup('financial', 'Financial', Color(0xFF059669), [
    E('revenue-summary', 'Revenue Summary', 'Daily revenue, expenses, net profit and occupancy trends', Icons.bar_chart),
    E('expense-report', 'Expense Report', 'Expenses grouped by category, vendor and period', Icons.attach_money),
    E('billing-report', 'Billing & Payments', 'Guest charges, payments received, outstanding balances', Icons.credit_card),
    E(
      'payroll-report',
      'Payroll Report',
      'Staff payroll runs, totals by period, department breakdown',
      Icons.account_balance_wallet_outlined,
      dateMode: 'none',
    ),
    E(
      'cash-flow-report',
      'Cash Flow Report',
      'Money in/out across all cash accounts with running balances',
      Icons.account_balance_outlined,
    ),
    E(
      'guest-ledger',
      'Guest Ledger',
      'Unpaid invoices aged by due date — who owes what, and for how long',
      Icons.receipt_long_outlined,
      dateMode: 'none',
      isNew: true,
    ),
    E(
      'ancillary-revenue',
      'Ancillary Revenue',
      'Spend beyond the room — by charge type, per stay',
      Icons.shopping_cart_outlined,
      isNew: true,
    ),
    E(
      'staff-loans',
      'Employee Loans & Advances',
      'What each staff member owes, and what was advanced and repaid in the period',
      Icons.volunteer_activism_outlined,
      isNew: true,
    ),
  ]),
  RestaurantReportGroup('operations', 'Operations', Color(0xFF7C3AED), [
    E('bookings-report', 'Bookings Report', 'All bookings with status, dates, rates and source', Icons.event_available_outlined),
    E('guest-report', 'Guest Report', 'Guest list, repeat guests, VIP guests, nationality breakdown', Icons.group_outlined, dateMode: 'none'),
    E('occupancy-report', 'Occupancy & ADR', 'Occupancy rate, ADR, RevPAR trends from daily closings', Icons.bed_outlined),
    E('maintenance-report', 'Maintenance Report', 'Maintenance requests by status, priority and estimated cost', Icons.build_outlined),
    E(
      'loyalty-report',
      'Loyalty Programme',
      'Members and points by tier, earned and redeemed in the period',
      Icons.workspace_premium_outlined,
      isNew: true,
    ),
  ]),
  RestaurantReportGroup('restaurant', 'Restaurant & Bar', Color(0xFFEA580C), [
    E('restaurant-sales', 'Restaurant Sales', 'Restaurant orders, revenue by period, popular items', Icons.shopping_cart_outlined),
    E('menu-performance', 'Menu Performance', 'Best-selling items, category breakdown, pricing analysis', Icons.description_outlined, dateMode: 'none'),
  ]),
  RestaurantReportGroup('periodic', 'Periodic Reports', Color(0xFF0284C7), [
    E('daily-report', 'Daily Report', 'Daily snapshot — arrivals, departures, revenue, expenses, occupancy', Icons.calendar_today_outlined, dateMode: 'single'),
    E('weekly-report', 'Weekly Report', 'Weekly summary — bookings, revenue, expenses, occupancy trends', Icons.calendar_today_outlined),
    E(
      'monthly-report',
      'Monthly Report',
      'Monthly overview — revenue, expenses, profit, occupancy, guest stats',
      Icons.calendar_today_outlined,
    ),
  ]),
  RestaurantReportGroup('housekeeping', 'Housekeeping & Inventory', Color(0xFFE11D48), [
    E('housekeeping-report', 'Housekeeping Report', 'Task completion rates, turnaround times by status', Icons.fact_check_outlined),
    E('inventory-report', 'Inventory Report', 'Stock levels, low-stock alerts, reorder suggestions', Icons.description_outlined, dateMode: 'none'),
    E(
      'housekeeping-productivity',
      'Housekeeping Productivity',
      'Minutes per room and rooms per shift, by attendant',
      Icons.timer_outlined,
      isNew: true,
    ),
  ]),
  RestaurantReportGroup('revenue', 'Revenue Management', Color(0xFF4F46E5), [
    E('performance-kpis', 'Performance & KPIs', 'Occupancy, ADR, RevPAR, TRevPAR and GOPPAR for the period', Icons.speed, isNew: true),
    E('source-of-business', 'Source of Business', 'Room nights and revenue by booking channel, with lead time', Icons.public, isNew: true),
    E('booking-pace', 'Booking Pace', 'How far ahead bookings arrive, bucketed by lead time', Icons.update, isNew: true),
    E('room-type-performance', 'Room Type Performance', 'Occupancy, ADR and RevPAR for each room type', Icons.grid_view, isNew: true),
    E(
      'length-of-stay',
      'Length of Stay',
      'How long guests actually stay, and what each length is worth',
      Icons.nights_stay_outlined,
      isNew: true,
    ),
    E(
      'cancellations',
      'Cancellations',
      'Cancelled bookings and lost value, by the channel that produced them',
      Icons.event_busy_outlined,
      isNew: true,
    ),
  ]),
];

final allHotelReports = [for (final g in hotelReportGroups) ...g.reports];

({RestaurantReportEntry report, RestaurantReportGroup group})? findHotelReport(String slug) {
  for (final g in hotelReportGroups) {
    for (final r in g.reports) {
      if (r.slug == slug) return (report: r, group: g);
    }
  }
  return null;
}

void openHotelReportsCatalog(BuildContext context, Session session, Company company) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => HotelReportsCatalogScreen(session: session, company: company),
  ),
);

/// A report with a screen opens it; any other row goes wherever its href
/// leads today.
void openHotelReport(BuildContext context, Session session, Company company, String slug) {
  final screen = hotelReportScreen(session, company, slug);
  if (screen != null) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    return;
  }
  final r = findHotelReport(slug);
  openAppHref(context, session, company, '/hotel-reports/$slug', label: r?.report.title ?? 'Report');
}

class HotelReportsCatalogScreen extends StatelessWidget {
  const HotelReportsCatalogScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, session, company, href: '/hotel-reports');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: TColors.violet100, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.bar_chart, size: 22, color: TColors.violet700),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reports',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${allHotelReports.length} reports — filters, summary cards, and a PDF you can view before you download it.',
                      style: const TextStyle(fontSize: 13, color: TColors.slate500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final g in hotelReportGroups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: g.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      g.label.toUpperCase(),
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: .6, color: TColors.slate500),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('${g.reports.length}', style: const TextStyle(fontSize: 11.5, color: TColors.slate400)),
                ],
              ),
            ),
            for (final r in g.reports) ...[
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => openHotelReport(context, session, company, r.slug),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    decoration: BoxDecoration(
                      border: Border.all(color: TColors.slate200),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(color: g.color, borderRadius: BorderRadius.circular(7)),
                          child: Icon(r.icon, size: 16, color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate900),
                              ),
                              Text(
                                r.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, color: TColors.slate500),
                              ),
                            ],
                          ),
                        ),
                        if (r.isNew) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: TColors.violet100, borderRadius: BorderRadius.circular(999)),
                            child: const Text(
                              'New',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: TColors.violet700),
                            ),
                          ),
                        ],
                        // Always visible: a hover-only chevron cannot be reached on touch.
                        const Icon(Icons.chevron_right, size: 18, color: Color(0xFFCBD5E1)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
