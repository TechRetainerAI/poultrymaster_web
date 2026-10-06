import '../money/money_routes.dart';
import 'package:flutter/material.dart';

import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../custom_form.dart';
import '../../module_registry.dart';
import '../../web_page_screen.dart';
import '../sales/sales_screen.dart';
import '../trackers/tracker_routes.dart';
import 'closing_reports.dart';
import 'dashboard_screen.dart';
import 'money_reports.dart';
import 'other_reports.dart';
import 'poultry_report_screen.dart';
import 'profit_loss_screen.dart';
import 'report_defs.dart';
import 'reports_catalog_screen.dart';

/// Every Poultry report route that has a native screen. The sidebar, the All
/// pages sheet and the catalogue all route through this map.
final Map<String, PageScreenBuilder> poultryReportScreens = {
  '/poultry/reports': (s, c) => PoultryReportsCatalogScreen(session: s, company: c),
  for (final slug in poultryReportDefs.keys)
    // Profit & Loss renders the statement view, not the slug engine.
    if (slug != 'profit-loss') '/poultry/reports/$slug': (s, c) => PoultryReportScreen(session: s, company: c, slug: slug),
  '/poultry/reports/profit-loss': (s, c) => ProfitLossScreen(session: s, company: c),
  '/poultry/reports/production': (s, c) => PoultryDashboardScreen(session: s, company: c, view: 'production'),
  '/poultry/reports/financial': (s, c) => PoultryDashboardScreen(session: s, company: c, view: 'financial'),
  '/poultry/reports/daily': (s, c) => PoultryDashboardScreen(session: s, company: c, view: 'daily'),
  '/poultry/reports/more': (s, c) => PoultryDashboardScreen(session: s, company: c, view: 'insights'),
  '/reports': (s, c) => ReportsTabsScreen(session: s, company: c),
  '/poultry-daily-summary': (s, c) => DailyBusinessSummaryScreen(session: s, company: c),
  '/poultry-closing-report-daily': (s, c) => ClosingReportScreen(session: s, company: c),
  '/poultry-closing-report': (s, c) => ClosingByCategoryScreen(session: s, company: c),
  '/poultry/reports/cash-accounts': (s, c) => CashAccountReportScreen(session: s, company: c),
  '/poultry/reports/money': (s, c) => MoneyMovementScreen(session: s, company: c),
  '/poultry/reports/batch-production-summary': (s, c) => BatchProductionSummaryScreen(session: s, company: c),
  '/poultry-feed-production/reports': (s, c) => FeedProductionReportsScreen(session: s, company: c),
  '/poultry/reports/changes': (s, c) => ChangesReportScreen(session: s, company: c),
};

/// Opens a report link: its native screen, or the web page in-app.
void openReportHref(BuildContext context, Session session, Company company, String href, {required String label}) {
  final screen = poultryReportScreens[href];
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => screen != null
        ? screen(session, company)
        : WebPageScreen(label: label, href: href, company: company, session: session),
  ));
}

/// Follows any app link from a report (Settings, Cash Flow, Loans…): the
/// native screen when the app has one, otherwise the web page in-app.
void openAppHref(BuildContext context, Session session, Company company, String href, {required String label}) {
  final screen = pageScreens[href];
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => screen != null
        ? screen(session, company)
        : salesScreenForHref(href, session, company) ??
            moneyScreenForHref(href, session, company) ??
            trackerScreenForHref(href, session, company) ??
            WebPageScreen(label: label, href: href, company: company, session: session),
  ));
}
