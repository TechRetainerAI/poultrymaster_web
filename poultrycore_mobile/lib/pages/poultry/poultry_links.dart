import 'package:flutter/material.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../custom_form.dart';
import '../web_page_screen.dart';
import 'daily_closing_screen.dart';
import 'farm_completeness_screen.dart';
import 'feed_distribution_screen.dart';
import '../module_registry.dart';
import 'money/money_routes.dart';
import 'sales/sales_screen.dart';

/// Pages that read `?date=` on the web, opened natively on that day.
final Map<String, Widget Function(Session, Company, String?)> _dated = {
  '/poultry-farm-completeness': (s, c, d) => FarmCompletenessScreen(session: s, company: c, initialDate: d),
  '/poultry-daily-closing': (s, c, d) => DailyClosingScreen(session: s, company: c, initialDate: d),
  '/poultry-feed-distribution': (s, c, d) => FeedDistributionScreen(session: s, company: c, initialDate: d),
};

/// Follows a web link from inside a Poultry screen: a native screen when the
/// app has one (keeping `?date=`), otherwise the web page in-app.
void openPoultryHref(
  BuildContext context,
  Session session,
  Company company,
  String href, {
  required String label,
  Map<String, PageScreenBuilder> screens = const {},
}) {
  final uri = Uri.parse(href);
  final sales = salesScreenForHref(href, session, company);
  if (sales != null) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => sales));
    return;
  }
  final money = moneyScreenForHref(href, session, company);
  if (money != null) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => money));
    return;
  }
  final dated = _dated[uri.path];
  // A native page with no query to keep (Daily Closing's /customer-balances).
  final native = screens[uri.path] ?? pageScreens[uri.path];
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => dated != null
        ? dated(session, company, uri.queryParameters['date'])
        : native != null && uri.query.isEmpty
            ? native(session, company)
            : WebPageScreen(label: label, href: href, company: company, session: session),
  ));
}
